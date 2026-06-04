//! Animated WebP 解码器
//!
//! 用 `image-webp` crate 解,支持动画 WebP(VP8X + ANIM + ANMF chunks)和
//! 静态 WebP(VP8/VP8L)。
//!
//! 与 GIF/APNG 不同,image-webp 内部已处理 dispose/blend,直接给我们出每帧的
//! 全尺寸 RGBA(用 `read_frame` API)。我们只需要按帧组织即可。

use crate::{DecodeError, DecodedImage, Frame};
use image_webp::WebPDecoder;
use std::io::Cursor;

pub fn decode(bytes: &[u8]) -> Result<DecodedImage, DecodeError> {
    let cursor = Cursor::new(bytes);
    let mut decoder = WebPDecoder::new(cursor)
        .map_err(|e| DecodeError::Webp(format!("WebPDecoder::new: {}", e)))?;

    let (width, height) = decoder.dimensions();
    if width == 0 || height == 0 {
        return Err(DecodeError::Webp(format!(
            "invalid dimensions: {}x{}",
            width, height
        )));
    }

    // image-webp 0.2 通过 num_frames > 1 判断是否动画(没有专门 has_animation 方法)
    let frame_count_raw = decoder.num_frames();
    if frame_count_raw <= 1 {
        // 静态 WebP: 我们不处理(交给 Flutter 内置 codec)
        return Err(DecodeError::UnsupportedFormat);
    }

    // 设置背景色(0 = 透明)
    decoder.set_background_color([0, 0, 0, 0]).ok();

    // image-webp 0.2: LoopCount::Times 是 NonZero<u16>,要 .get() 取值
    let loop_count: u32 = match decoder.loop_count() {
        image_webp::LoopCount::Forever => 0,
        image_webp::LoopCount::Times(n) => n.get() as u32,
    };

    let frame_count = frame_count_raw as usize;
    if frame_count == 0 {
        return Err(DecodeError::EmptyFrames);
    }

    let canvas_size = (width as usize) * (height as usize) * 4;
    let mut frames: Vec<Frame> = Vec::with_capacity(frame_count);

    for _ in 0..frame_count {
        let mut buf = vec![0u8; canvas_size];
        let delay_ms = decoder
            .read_frame(&mut buf)
            .map_err(|e| DecodeError::Webp(format!("read_frame: {}", e)))?;

        // image-webp 0.2 read_frame 返回 delay_ms (u32) 类型
        let delay_ms_u32 = delay_ms as u32;
        frames.push(Frame {
            rgba: buf,
            delay_ms: if delay_ms_u32 == 0 { 100 } else { delay_ms_u32 },
        });
    }

    Ok(DecodedImage {
        width,
        height,
        loop_count,
        frames,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_invalid_webp_data() {
        // 不是合法 WebP → 报错
        let bad = b"not a webp";
        assert!(decode(bad).is_err());
    }

    // 真实 WebP fixture(静态/动画各一)由后续 build 准备阶段添加
}
