//! C FFI 接口 — dart:ffi 端通过这些函数与 Rust 解码器通信。
//!
//! 错误码约定:
//!   0  = success
//!  -1  = invalid input (null pointer / empty bytes / too short)
//!  -2  = unsupported format (magic bytes not recognized)
//!  -3  = decode error (decoder threw error)
//!  -4  = handle not found
//!  -5  = frame index out of range

use crate::{decode_bytes, register, release, with_image, DecodeError};
use std::ffi::{c_char, CString};
use std::sync::OnceLock;

const ERR_OK: i32 = 0;
const ERR_INVALID: i32 = -1;
const ERR_UNSUPPORTED: i32 = -2;
const ERR_DECODE: i32 = -3;
const ERR_HANDLE_NOT_FOUND: i32 = -4;
const ERR_FRAME_OOR: i32 = -5;

/// 解码动图字节流,成功时返回 handle(写入 *out_handle),失败返回错误码
///
/// # Safety
/// - `bytes` 必须指向至少 `len` 字节的有效内存
/// - `out_handle` 必须是有效的 *mut u64
///
/// dart 端调用方:
///   final outHandle = calloc<Uint64>();
///   final rc = lib.native_animated_image_decode(bytesPtr, len, outHandle);
///   final handle = outHandle.value;
///   calloc.free(outHandle);
#[no_mangle]
pub unsafe extern "C" fn native_animated_image_decode(
    bytes: *const u8,
    len: usize,
    out_handle: *mut u64,
) -> i32 {
    if bytes.is_null() || out_handle.is_null() || len == 0 {
        return ERR_INVALID;
    }

    let slice = std::slice::from_raw_parts(bytes, len);
    match decode_bytes(slice) {
        Ok(image) => {
            let handle = register(image);
            *out_handle = handle;
            ERR_OK
        }
        Err(DecodeError::InvalidInput) => ERR_INVALID,
        Err(DecodeError::UnsupportedFormat) => ERR_UNSUPPORTED,
        Err(DecodeError::EmptyFrames)
        | Err(DecodeError::Gif(_))
        | Err(DecodeError::Png(_))
        | Err(DecodeError::Webp(_)) => ERR_DECODE,
    }
}

/// 取 handle 对应解码结果的 metadata JSON(width/height/frame_count/frames[delay_ms])
///
/// 返回指针:成功 = 拥有所有权的 C 字符串(调用方负责 free 通过 `native_animated_image_free_string`);
/// 失败 = NULL
///
/// # Safety
/// - 返回的字符串必须用 `native_animated_image_free_string` 释放,不能用 free()
#[no_mangle]
pub extern "C" fn native_animated_image_get_metadata_json(handle: u64) -> *mut c_char {
    let json = with_image(handle, |img| {
        let meta = img.to_metadata();
        serde_json::to_string(&meta).ok()
    });

    match json {
        Some(Some(s)) => match CString::new(s) {
            Ok(cstr) => cstr.into_raw(),
            Err(_) => std::ptr::null_mut(),
        },
        _ => std::ptr::null_mut(),
    }
}

/// 取某帧的 RGBA 数据指针(零拷贝)+ 长度
///
/// 返回指针生命周期:与 handle 绑定,在 `native_animated_image_release` 之前一直有效
///
/// # Safety
/// - `out_ptr` 和 `out_len` 必须是有效指针
/// - 返回指针指向的内存归 handle 所有,**不要 free**
/// - dart 端只能 readonly 读取,持有期间不能跨过 release 调用
#[no_mangle]
pub unsafe extern "C" fn native_animated_image_get_frame_rgba(
    handle: u64,
    frame_idx: u32,
    out_ptr: *mut *const u8,
    out_len: *mut usize,
) -> i32 {
    if out_ptr.is_null() || out_len.is_null() {
        return ERR_INVALID;
    }

    // 这里有个生命周期挑战:with_image 借用是临时的,但我们要返回指向 frame.rgba 的指针给 dart
    // 解决:registry 的 Mutex 保证 image 在 handle 存在期间是 stable 的(Vec 不会 reallocate
    // 除非有人 mutate,我们的设计是 decoded 后只读),所以指针有效期 = handle 生命周期
    //
    // 用 raw pointer 从 with_image 闭包内拿出来 — 闭包返回 (ptr, len)
    let result = with_image(handle, |img| {
        img.frames.get(frame_idx as usize).map(|f| (f.rgba.as_ptr(), f.rgba.len()))
    });

    match result {
        Some(Some((ptr, len))) => {
            *out_ptr = ptr;
            *out_len = len;
            ERR_OK
        }
        Some(None) => ERR_FRAME_OOR,
        None => ERR_HANDLE_NOT_FOUND,
    }
}

/// 释放 handle 对应的解码结果(整张图所有帧 + metadata)
///
/// 释放后,该 handle 不可再用;之前从 `get_frame_rgba` 拿到的指针也立即失效
#[no_mangle]
pub extern "C" fn native_animated_image_release(handle: u64) {
    release(handle);
}

/// 释放 `get_metadata_json` 返回的字符串
///
/// # Safety
/// - `s` 必须是 `native_animated_image_get_metadata_json` 返回的指针,或 NULL
#[no_mangle]
pub unsafe extern "C" fn native_animated_image_free_string(s: *mut c_char) {
    if s.is_null() {
        return;
    }
    let _ = CString::from_raw(s);
}

/// 返回 codec 版本字符串(语义版本)
///
/// dart 端用于运行时检测 binary 与 dart 包是否兼容
///
/// 返回静态字符串,无需释放
#[no_mangle]
pub extern "C" fn native_animated_image_version() -> *const c_char {
    static VERSION: OnceLock<CString> = OnceLock::new();
    let v = VERSION.get_or_init(|| {
        CString::new(env!("CARGO_PKG_VERSION")).expect("version contains no NUL")
    });
    v.as_ptr()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::ffi::CStr;

    /// 最小 GIF89a 1x1
    const TINY_GIF: &[u8] = &[
        0x47, 0x49, 0x46, 0x38, 0x39, 0x61, 0x01, 0x00, 0x01, 0x00, 0x80, 0x00, 0x00, 0x00, 0x00,
        0x00, 0xff, 0xff, 0xff, 0x21, 0xf9, 0x04, 0x00, 0x00, 0x00, 0x00, 0x00, 0x2c, 0x00, 0x00,
        0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00, 0x02, 0x02, 0x4c, 0x01, 0x00, 0x3b,
    ];

    #[test]
    fn ffi_full_lifecycle() {
        // 1. decode
        let mut handle: u64 = 0;
        let rc = unsafe {
            native_animated_image_decode(TINY_GIF.as_ptr(), TINY_GIF.len(), &mut handle)
        };
        assert_eq!(rc, ERR_OK);
        assert!(handle > 0);

        // 2. get metadata
        let meta_ptr = native_animated_image_get_metadata_json(handle);
        assert!(!meta_ptr.is_null());
        let meta_str = unsafe { CStr::from_ptr(meta_ptr) }.to_str().unwrap();
        assert!(meta_str.contains("\"width\":1"));
        assert!(meta_str.contains("\"frame_count\":1"));
        unsafe { native_animated_image_free_string(meta_ptr) };

        // 3. get frame RGBA
        let mut frame_ptr: *const u8 = std::ptr::null();
        let mut frame_len: usize = 0;
        let rc = unsafe {
            native_animated_image_get_frame_rgba(handle, 0, &mut frame_ptr, &mut frame_len)
        };
        assert_eq!(rc, ERR_OK);
        assert!(!frame_ptr.is_null());
        assert_eq!(frame_len, 4); // 1*1*4

        // 4. frame out of range
        let rc_oor = unsafe {
            native_animated_image_get_frame_rgba(handle, 99, &mut frame_ptr, &mut frame_len)
        };
        assert_eq!(rc_oor, ERR_FRAME_OOR);

        // 5. release
        native_animated_image_release(handle);

        // 6. handle gone
        let rc_gone = unsafe {
            native_animated_image_get_frame_rgba(handle, 0, &mut frame_ptr, &mut frame_len)
        };
        assert_eq!(rc_gone, ERR_HANDLE_NOT_FOUND);
    }

    #[test]
    fn ffi_decode_invalid_input() {
        let mut handle: u64 = 0;

        // null pointer
        let rc = unsafe { native_animated_image_decode(std::ptr::null(), 0, &mut handle) };
        assert_eq!(rc, ERR_INVALID);

        // empty
        let rc = unsafe { native_animated_image_decode([].as_ptr(), 0, &mut handle) };
        assert_eq!(rc, ERR_INVALID);

        // null out_handle
        let rc = unsafe {
            native_animated_image_decode(TINY_GIF.as_ptr(), TINY_GIF.len(), std::ptr::null_mut())
        };
        assert_eq!(rc, ERR_INVALID);
    }

    #[test]
    fn ffi_decode_unsupported() {
        // JPEG magic bytes — dispatcher 不识别,返 ERR_UNSUPPORTED
        let jpeg_bytes = b"\xff\xd8\xff\xe0\x00\x10JFIF\x00\x01";
        let mut handle: u64 = 0;
        let rc = unsafe {
            native_animated_image_decode(jpeg_bytes.as_ptr(), jpeg_bytes.len(), &mut handle)
        };
        assert_eq!(rc, ERR_UNSUPPORTED);
    }

    #[test]
    fn ffi_version() {
        let ptr = native_animated_image_version();
        assert!(!ptr.is_null());
        let v = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap();
        assert!(!v.is_empty());
        // 形如 "0.1.0"
        assert!(v.split('.').count() >= 2);
    }
}
