#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <unistd.h>
#include <fcntl.h>
#include <termios.h>
#include <sys/select.h>
#include <sys/time.h>

#define PORT "/dev/ttyS1"
#define BAUD B115200

#define CMD_INIT       0x01
#define CMD_CONFIG     0x02
#define CMD_SET_SPEEDS 0x13
#define RSP_ACK        0x80

#define PASS "\033[92m[PASS]\033[0m"
#define FAIL "\033[91m[FAIL]\033[0m"
#define INFO "\033[94m[INFO]\033[0m"

int init_serial(const char* port) {
    int fd = open(port, O_RDWR | O_NOCTTY | O_NDELAY);
    if (fd < 0) {
        perror("打开串口失败");
        return -1;
    }
    struct termios tty;
    if (tcgetattr(fd, &tty) != 0) {
        perror("获取串口属性失败");
        return -1;
    }
    cfmakeraw(&tty);
    cfsetospeed(&tty, BAUD);
    cfsetispeed(&tty, BAUD);
    
    tty.c_cc[VMIN]  = 0;
    tty.c_cc[VTIME] = 1; // 100ms timeout per read

    if (tcsetattr(fd, TCSANOW, &tty) != 0) {
        perror("设置串口属性失败");
        return -1;
    }
    // 清空缓冲区
    tcflush(fd, TCIOFLUSH);
    return fd;
}

void build_frame(uint8_t cmd, const uint8_t* payload, uint8_t len, uint8_t* out, int* out_len) {
    out[0] = 0xAA;
    out[1] = 0x55;
    out[2] = cmd;
    out[3] = len;
    
    uint8_t chk = cmd ^ len;
    for (int i = 0; i < len; i++) {
        out[4 + i] = payload[i];
        chk ^= payload[i];
    }
    out[4 + len] = chk;
    *out_len = 5 + len;
}

int recv_frame(int fd, uint8_t* out_cmd, uint8_t* out_payload, uint8_t* out_len) {
    uint8_t b;
    int state = 0;
    uint8_t cmd = 0, len = 0, chk = 0, chk_calc = 0;
    uint8_t p_idx = 0;

    struct timeval tv;
    fd_set fds;
    
    // 超时机制 1秒
    tv.tv_sec = 1;
    tv.tv_usec = 0;

    while (1) {
        FD_ZERO(&fds);
        FD_SET(fd, &fds);
        if (select(fd + 1, &fds, NULL, NULL, &tv) <= 0) {
            return -1; // Timeout
        }

        if (read(fd, &b, 1) <= 0) continue;

        switch (state) {
            case 0: if (b == 0xAA) state = 1; break;
            case 1: if (b == 0x55) state = 2; else state = 0; break;
            case 2: cmd = b; state = 3; break;
            case 3: len = b; state = (len > 0) ? 4 : 5; break;
            case 4: 
                out_payload[p_idx++] = b;
                if (p_idx == len) state = 5;
                break;
            case 5:
                chk = b;
                chk_calc = cmd ^ len;
                for (int i = 0; i < len; i++) chk_calc ^= out_payload[i];
                if (chk == chk_calc) {
                    *out_cmd = cmd;
                    *out_len = len;
                    return 0; // Success
                }
                return -2; // Checksum error
        }
    }
}

int send_and_wait_ack(int fd, uint8_t cmd, const uint8_t* payload, uint8_t len, const char* name) {
    uint8_t frame[256];
    int frame_len;
    build_frame(cmd, payload, len, frame, &frame_len);
    
    tcflush(fd, TCIOFLUSH);
    write(fd, frame, frame_len);

    uint8_t r_cmd, r_payload[256], r_len;
    if (recv_frame(fd, &r_cmd, r_payload, &r_len) == 0) {
        if (r_cmd == RSP_ACK) {
            printf("  %s %s\n", PASS, name);
            return 1;
        } else {
            printf("  %s %s (收到 NACK 或其他: 0x%02X)\n", FAIL, name, r_cmd);
            return 0;
        }
    }
    printf("  %s %s (超时无响应)\n", FAIL, name);
    return 0;
}

// 组装大端序的 int16_t (对应 Python 的 >hh)
void pack_hh(int16_t v1, int16_t v2, uint8_t* buf) {
    buf[0] = (v1 >> 8) & 0xFF;
    buf[1] = v1 & 0xFF;
    buf[2] = (v2 >> 8) & 0xFF;
    buf[3] = v2 & 0xFF;
}

int main() {
    printf("==================================================\n");
    printf("  ESP32-C3 电机控制器 UART C语言直驱测试\n");
    printf("  端口: %s  波特率: 115200\n", PORT);
    printf("==================================================\n\n");

    int fd = init_serial(PORT);
    if (fd < 0) return 1;

    usleep(500000); // 500ms 等待稳定

    printf("%s ── 初始化电机控制器 ──\n", INFO);
    send_and_wait_ack(fd, CMD_INIT, NULL, 0, "INIT");
    
    uint8_t config_payload[4];
    pack_hh(4680, 20000, config_payload); // PPR=4680, FREQ=20000
    send_and_wait_ack(fd, CMD_CONFIG, config_payload, 4, "CONFIG (4680, 20000Hz)");

    printf("\n%s ── 测试 SET_SPEEDS (双电机控制) ──\n", INFO);
    uint8_t speed_payload[4];

    // M1=200, M2=200
    pack_hh(200, 200, speed_payload);
    send_and_wait_ack(fd, CMD_SET_SPEEDS, speed_payload, 4, "双电机正转 (200, 200)");
    usleep(500000);

    // M1=-200, M2=-200
    pack_hh(-200, -200, speed_payload);
    send_and_wait_ack(fd, CMD_SET_SPEEDS, speed_payload, 4, "双电机反转 (-200, -200)");
    usleep(500000);

    // M1=180, M2=-180
    pack_hh(180, -180, speed_payload);
    send_and_wait_ack(fd, CMD_SET_SPEEDS, speed_payload, 4, "双电机反向/原地旋转 (180, -180)");
    usleep(1000000);

    // M1=0, M2=0 停止
    pack_hh(0, 0, speed_payload);
    send_and_wait_ack(fd, CMD_SET_SPEEDS, speed_payload, 4, "双电机同时停止 (0, 0)");
    usleep(500000);

    close(fd);
    printf("\n测试完成，电机已停止！\n");
    return 0;
}
