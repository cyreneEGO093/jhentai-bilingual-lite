# Experimental Android OCR provenance

This optional component is part of the GPL-3.0-only derivative. Original third-party licenses remain applicable. Versions are pinned; no Python interpreter, Qt application, manga-translator-ui code, Comic Text Detector weights or inpainting models are included.

| Component | Version/source | License |
| --- | --- | --- |
| ONNX Runtime Android | `com.microsoft.onnxruntime:onnxruntime-android:1.30.0`, https://github.com/microsoft/onnxruntime/tree/v1.30.0 | MIT; upstream third-party notices preserved |
| OpenCV Android | `org.opencv:opencv:4.12.0`, https://github.com/opencv/opencv/tree/4.12.0 | Apache-2.0; upstream third-party notices preserved |
| Model conventions and downloadable models | RapidAI/RapidOCR `v3.9.2`, https://github.com/RapidAI/RapidOCR/tree/v3.9.2 and https://www.modelscope.cn/models/RapidAI/RapidOCR | Apache-2.0 as declared in the preserved model card and RapidOCR license |

The Kotlin detection, rotated-rectangle expansion, perspective crop and greedy CTC decoder are independently implemented. BGR normalization and the model's embedded character dictionary follow the fixed model contract. This is not a verbatim port of RapidOCR's Python detector postprocessor and does not implement semantic bubble detection.

Weights are downloaded only on explicit user action; they are not bundled in the application/source archives. The base URL is `https://www.modelscope.cn/models/RapidAI/RapidOCR/resolve/v3.9.2/onnx/PP-OCRv6/`.

| Relative path | Bytes | SHA-256 |
| --- | ---: | --- |
| `det/PP-OCRv6_det_small.onnx` | 9929594 | `090f04abcd9d9a7498bc4ebf677e4cb9bdce1fe4197ddb7e529f1ef44e1ff94f` |
| `rec/PP-OCRv6_rec_small.onnx` | 21234383 | `6f327246b50388f3c176ae304bd95767ea6dc0c9ae92153ef8cbe210b3c14884` |

Downloads reject mismatching sizes/hashes; native inference also checks hashes. The models and provider can change availability; changed bytes are rejected rather than silently accepted. Preserve this model card, attribution and Apache-2.0 license if separately redistributing the weights.

`onnxruntime-ThirdPartyNotices.txt` is from the pinned upstream release. `opencv-ThirdPartyNotices.txt` preserves license/copyright/notice files under the pinned OpenCV source's `3rdparty/` directory, including optional components which may not be compiled into Android. The original primary licenses are included separately. This folder is included in the application's license screen.

The Android OpenCV binary also uses oneTBB 2022.1.0, ADE 0.1.2e and KleidiCV 0.5.0 (Apache-2.0); their license texts are appended to the OpenCV third-party notices, and matching sources accompany the native source supplement. Intel ITT is used under its BSD-3-Clause alternative; that text and the IJG README are preserved too. This software is based in part on the work of the Independent JPEG Group. OpenCV's embedded build information reports no non-free algorithms and Android Media NDK video I/O (no FFmpeg).

OpenCV source archive: https://github.com/opencv/opencv/archive/refs/tags/4.12.0.zip ; retrieved archive SHA-256 `fa3faf7581f1fa943c9e670cf57dd6ba1c5b4178f363a188a2c8bff1eb28b7e4` is not used for model validation.
