// File: os/StarryOS/kernel/src/pseudofs/dev/uvc/mod.rs

use alloc::sync::Arc;
use core::any::Any;

use ax_errno::AxError;
use axfs_ng_vfs::{NodeFlags, VfsResult};

use crate::pseudofs::DeviceOps;

// V4L2 IOCTL magic numbers
const VIDIOC_QUERYCAP: u32 = 0x80685600;
const VIDIOC_STREAMON: u32 = 0x40045612;

/// Virtual File System node for V4L2 video devices.
pub struct VideoNode {
    // TODO: Inject Arc<Mutex<FrameParser>> and USB Endpoint handles here in subsequent iterations.
}

impl VideoNode {
    pub fn new() -> Self {
        Self {}
    }
}

impl DeviceOps for VideoNode {
    fn read_at(&self, _buf: &mut [u8], _offset: u64) -> VfsResult<usize> {
        warn!("[V4L2] 应用程序尝试读取 /dev/video0 (read_at)");
        // Returns 0 temporarily. Will be linked to FrameParser output later.
        Ok(0)
    }

    fn write_at(&self, _buf: &[u8], _offset: u64) -> VfsResult<usize> {
        Err(AxError::Unsupported)
    }

    fn ioctl(&self, cmd: u32, _arg: usize) -> VfsResult<usize> {
        match cmd {
            VIDIOC_QUERYCAP => {
                warn!("[V4L2] 拦截到 IOCTL: VIDIOC_QUERYCAP");
                // TODO: Populate standard v4l2_capability struct and copy to user space.
                Ok(0)
            }
            VIDIOC_STREAMON => {
                warn!("[V4L2] 拦截到 IOCTL: VIDIOC_STREAMON, 准备唤醒硬件");
                // TODO: Trigger UVC Probe/Commit control transfers and start async data pump.
                Ok(0)
            }
            _ => {
                warn!("[V4L2] 收到未支持的 IOCTL 命令码: 0x{:x}", cmd);
                Err(AxError::Unsupported)
            }
        }
    }

    fn as_any(&self) -> &dyn Any {
        self
    }

    fn flags(&self) -> NodeFlags {
        NodeFlags::NON_CACHEABLE | NodeFlags::STREAM
    }
}
