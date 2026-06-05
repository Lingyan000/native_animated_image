//! AVIF 解码器(纯 Rust)
//!
//! 用 [`zenavif`](https://crates.io/crates/zenavif) 解 AVIF —— 内部组合
//! `rav1d-safe`(dav1d 的 Rust port,带 safe SIMD)+ `zenavif-parse`(ISO BMFF
//! demuxer,支持 animation / grid / alpha)。100% safe Rust,无 C 依赖,
//! 5 端 cargo build 都能跑。
//!
//! 在 native_animated_image v0.2.0 中,AVIF 主路径走平台 ImageIO/ImageDecoder
//! (iOS 16.4+/macOS 13.4+/Android 31+)—— Apple 的实现更快。这个 Rust 解码器
//! 作为**回退**:
//! - Android 上 `ImageDecoder` 能解 animated AVIF 但不让我们逐帧抓 → 走 Rust
//! - 老系统(iOS < 16.4 / Android < 31 / Windows / Linux)无系统 AVIF decoder
//!
//! 性能跟 flutter_avif / Chromium dav1d 同档(rav1d 比 dav1d 慢 ~5%),
//! 不是优势路径,只为"能跑"和"绕开 flutter_avif 包带来的代码膨胀"。

use crate::{DecodeError, DecodedImage, Frame};
use zenpixels_convert::ext::PixelBufferConvertTypedExt;

pub fn decode(bytes: &[u8]) -> Result<DecodedImage, DecodeError> {
    // 先 try 动画解码 —— 静态 AVIF 会被识别为 1 帧动画,所以这条路径同时
    // 覆盖 static + animated。decode_animation 内部对静态 AVIF 也 OK。
    match zenavif::decode_animation(bytes) {
        Ok(anim) => convert_animation(anim),
        Err(_anim_err) => {
            // 部分 AVIF(可能 strict-static 容器)走 still decode 反而 OK
            let still =
                zenavif::decode(bytes).map_err(|e| DecodeError::Avif(format!("decode: {}", e)))?;
            let (w, h, rgba) = pixel_buffer_to_rgba(&still)?;
            Ok(DecodedImage {
                width: w,
                height: h,
                loop_count: 0,
                frames: vec![Frame { rgba, delay_ms: 0 }],
            })
        }
    }
}

fn convert_animation(anim: zenavif::DecodedAnimation) -> Result<DecodedImage, DecodeError> {
    if anim.frames.is_empty() {
        return Err(DecodeError::EmptyFrames);
    }
    // zenavif 把 loop_count 放在 anim.info,0 表示无限循环 — 跟 GIF/APNG 一致
    let loop_count = anim.info.loop_count;

    // 用第 1 帧确定 canvas 尺寸(animated AVIF 所有帧都是同 canvas size)
    let (first_w, first_h, _) = pixel_buffer_to_rgba(&anim.frames[0].pixels)?;

    let mut frames = Vec::with_capacity(anim.frames.len());
    for frame in anim.frames {
        let (_w, _h, rgba) = pixel_buffer_to_rgba(&frame.pixels)?;
        let delay_ms = if frame.duration_ms == 0 {
            100
        } else {
            frame.duration_ms
        };
        frames.push(Frame { rgba, delay_ms });
    }

    Ok(DecodedImage {
        width: first_w,
        height: first_h,
        loop_count,
        frames,
    })
}

/// 把 zenavif 返回的 PixelBuffer 统一转成 tightly-packed RGBA8888,
/// dart 端可以直接 `ui.decodeImageFromPixels(..., PixelFormat.rgba8888)` 消费。
fn pixel_buffer_to_rgba(buf: &zenavif::PixelBuffer) -> Result<(u32, u32, Vec<u8>), DecodeError> {
    let w = buf.width();
    let h = buf.height();
    // to_rgba8 来自 zenpixels-convert 的 ext trait,自动处理任何源格式
    // (RGB/YUV/HDR/各色彩空间)转 sRGB RGBA8。allocating but 干净。
    let rgba_buf = buf.to_rgba8();
    let bytes = rgba_buf
        .as_contiguous_bytes()
        .ok_or_else(|| DecodeError::Avif("RGBA buffer not contiguous".into()))?;
    Ok((w, h, bytes.to_vec()))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn invalid_input_fails_gracefully() {
        let result = decode(b"not an avif file");
        assert!(result.is_err());
    }

    // Real AVIF fixture tests live in tests/ folder once we add sample
    // files (Step 2 of v0.2.1).
}
