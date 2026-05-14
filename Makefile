# =================================================================
# StarryOS RK3588 Deployment System (Mac Optimized Version)
# =================================================================

# -----------------------------------------------------------------
# Path Definitions
# -----------------------------------------------------------------
ROOT_DIR     := $(shell pwd)
TOOLS_DIR    := $(ROOT_DIR)/tools
OUT_DIR      := $(ROOT_DIR)/out

# Rust 编译出来的原始二进制文件路径
KERNEL_BIN   := $(ROOT_DIR)/target/aarch64-unknown-none-softfloat/release/starryos.bin

# Build Artifacts (中间产物，自动存放在 out 目录)
KERNEL_UIMG  := $(OUT_DIR)/StarryOS_aarch64-dyn.uimg

# 直接指向你源码树里的真实 DTB 文件
DTB_FILE     := $(ROOT_DIR)/os/StarryOS/configs/board/orangepi-5-plus.dtb

# U-Boot & Flash Tools (需要确保 tools 目录里有这些文件)
BOOT_CMD     := $(TOOLS_DIR)/boot.cmd
BOOT_SCR     := $(OUT_DIR)/boot.scr
BOOT_IMG     := $(OUT_DIR)/boot.img
LOADER_BIN   := $(TOOLS_DIR)/MiniLoaderAll.bin
PARAM_TXT    := $(TOOLS_DIR)/parameter.txt

# Flash Tooling (Rockchip Specific)
RK_TOOL      := sudo rkdeveloptool

# UI Terminal Colors
GREEN  := \033[0;32m
CYAN   := \033[0;36m
YELLOW := \033[0;33m
RED    := \033[0;31m
NC     := \033[0m

# -----------------------------------------------------------------
# Targets
# -----------------------------------------------------------------
.PHONY: check-path rk-image rk-flash rk-clean deploy

deploy: rk-image rk-flash

check-path:
	@echo "$(YELLOW)===== StarryOS RK3588 Path Check =====$(NC)"
	@echo "Current Workdir:   $(CURDIR)"
	@echo "---------------------------------------"
	@echo "$(CYAN)[Build Artifacts]$(NC)"
	@printf "Kernel Bin (.bin): %-40s " "$(KERNEL_BIN)"
	@[ -f "$(KERNEL_BIN)" ] && echo "$(GREEN)[OK]$(NC)" || echo "$(RED)[MISSING - 请先执行 cargo xtask build]$(NC)"
	@printf "Device Tree (DTB): %-40s " "$(DTB_FILE)"
	@[ -f "$(DTB_FILE)" ] && echo "$(GREEN)[OK]$(NC)" || echo "$(RED)[MISSING]$(NC)"
	@echo "\n$(CYAN)[Hardware/Tooling]$(NC)"
	@printf "Parameter File:    %-40s " "$(PARAM_TXT)"
	@[ -f "$(PARAM_TXT)" ] && echo "$(GREEN)[OK]$(NC)" || echo "$(RED)[MISSING]$(NC)"
	@printf "MiniLoader Bin:    %-40s " "$(LOADER_BIN)"
	@[ -f "$(LOADER_BIN)" ] && echo "$(GREEN)[OK]$(NC)" || echo "$(RED)[MISSING]$(NC)"
	@printf "Boot Command:      %-40s " "$(BOOT_CMD)"
	@[ -f "$(BOOT_CMD)" ] && echo "$(GREEN)[OK]$(NC)" || echo "$(RED)[MISSING]$(NC)"
	@echo "$(YELLOW)=======================================$(NC)"

rk-image:
	@echo "$(CYAN)[BUILD] Packaging Rust .bin to uImage...$(NC)"
	@if [ ! -f "$(KERNEL_BIN)" ]; then echo "$(RED)Error: 没找到 $(KERNEL_BIN)，请先编译！$(NC)"; exit 1; fi
	@mkdir -p $(OUT_DIR)
	@mkimage -A arm64 -O linux -T kernel -C none -a 0x40000000 -e 0x40000000 -n "StarryOS" -d $(KERNEL_BIN) $(KERNEL_UIMG) > /dev/null

	@echo "$(CYAN)[IMAGE] Validating build environment...$(NC)"
	@which mkfs.ext4 mkimage resize2fs e2fsck > /dev/null || (echo "$(RED)Error: Missing tools.$(NC)" && exit 1)
	@echo "$(CYAN)[IMAGE] Generating boot.scr...$(NC)"
	@mkimage -A arm -T script -C none -n "TF boot" -d $(BOOT_CMD) $(BOOT_SCR) > /dev/null
	
	@echo "$(CYAN)[IMAGE] 准备文件到临时目录...$(NC)"
	@rm -rf $(OUT_DIR)/boot_payload
	@mkdir -p $(OUT_DIR)/boot_payload
	@cp $(BOOT_SCR) $(OUT_DIR)/boot_payload/
	@cp $(KERNEL_UIMG) $(OUT_DIR)/boot_payload/kernel.uimg
	@cp $(DTB_FILE) $(OUT_DIR)/boot_payload/rk3588-orangepi-5-plus.dtb
	
	@echo "$(CYAN)[IMAGE] 生成 128MB ext4 镜像 (Mac 安全模式，无需挂载)...$(NC)"
	@dd if=/dev/zero of=$(BOOT_IMG) bs=1M count=128 status=none
	@mkfs.ext4 -F -q -L "STARRY_BOOT" -d $(OUT_DIR)/boot_payload $(BOOT_IMG) > /dev/null
	@rm -rf $(OUT_DIR)/boot_payload
	
	@echo "$(CYAN)[IMAGE] Optimizing image size (resize2fs)...$(NC)"
	@e2fsck -f -y $(BOOT_IMG) > /dev/null
	@resize2fs -M $(BOOT_IMG) > /dev/null
	@echo "$(GREEN)[SUCCESS] Image ready: $(BOOT_IMG) ($$(du -h $(BOOT_IMG) | cut -f1))$(NC)"

rk-flash:
	@echo "$(YELLOW)[FLASH] Polling for Maskrom device...$(NC)"
	@while ! $(RK_TOOL) ld | grep -q "Maskrom"; do sleep 1; done
	@echo "$(CYAN)[FLASH] Initializing Download-Boot (db)...$(NC)"
	@$(RK_TOOL) db $(LOADER_BIN)
	@sleep 2
	@echo "$(CYAN)[FLASH] Selecting Storage: SD Card (cs 2)...$(NC)"
	@$(RK_TOOL) cs 2
	@echo "$(CYAN)[FLASH] Synchronizing GPT Table...$(NC)"
	@$(RK_TOOL) gpt $(PARAM_TXT)
	@$(RK_TOOL) ppt
	@sleep 1
	@echo "$(CYAN)[FLASH] Writing BOOT...$(NC)"
	@$(RK_TOOL) wlx boot $(BOOT_IMG)
	@echo "$(GREEN)[SUCCESS] Deployment complete. Resetting...$(NC)"
	@$(RK_TOOL) rd

rk-clean:
	@rm -rf $(OUT_DIR)
	@echo "$(GREEN)[CLEAN] Workspace cleaned.$(NC)"