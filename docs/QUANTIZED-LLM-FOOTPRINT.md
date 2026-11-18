# Quantized LLM footprint and StackAlign deployment boundary

**Status: engineering guidance; no model artifact is included or deployed by this change.**

This document evaluates whether `ljrseals-dev/schema` can reduce the storage footprint of the model described in `ljrseals-dev/shadowy-spooky-poltergeist`, and defines a safe path for using a smaller model with StackAlign.

## Executive finding

The current `schema-review` package is **not a model quantizer**. Its `execute_and_validate` runtime accepts already-decoded tensor payloads and performs these transforms:

- FLOAT16 words -> float32-valued Python floats;
- signed INT8 values -> dequantized float32-valued Python floats;
- explicitly packed two-bit ternary values -> decoded float32-valued Python floats.

Those operations decode or expand an already-quantized representation. They do not take a full-precision model and emit a smaller quantized checkpoint. The package also does not parse ONNX protobufs, discover initializer tensors, quantize weights, rewrite a graph, or produce a runnable model file.

The schema package can become a **validation component** in a future quantization pipeline, but it cannot by itself shrink the model today. Its independent reference calculations check the numeric decoding implementation; they do not establish end-to-end model quality, ONNX Runtime parity, or task-quality retention.

## What the current model specification implies

The `shadowy-spooky-poltergeist` specification describes 550–760 billion total parameters, with approximately 8B active during prefill and 16B during decode. Active parameters are not the same as stored parameters: an MoE runtime still needs access to the expert weights selected over time. The repository is a static specification, not a checkpoint or runnable implementation.

Raw weight storage lower bounds, using decimal GB/TB and excluding scales, metadata, alignment, tokenizer, runtime, KV cache, and allocator overhead:

| Representation | Bytes per parameter | 550B parameters | 760B parameters |
|---|---:|---:|---:|
| BF16 / FP16 | 2 | 1.10 TB | 1.52 TB |
| INT8 | 1 | 550 GB | 760 GB |
| packed 2-bit | 0.25 | 137.5 GB | 190 GB |

These are arithmetic lower bounds, not measured artifact sizes. The schema package's ternary decoder uses two bits per stored symbol; do not substitute the theoretical entropy of ternary symbols for the actual packed format.

For comparison, an independently trained or distilled **dense 8B model** would have raw weight lower bounds of about 16 GB at BF16, 8 GB at INT8, or 2 GB at packed 2-bit. A 4-bit representation would be about 4 GB, but the current schema package does not implement 4-bit quantization or a 4-bit decoder. These figures still exclude runtime memory and context/KV cache.

Reducing the proposed 550–760B MoE to a practical single-server model is therefore not a matter of changing the active-parameter setting. It requires selecting an existing smaller model or training/distilling a new smaller architecture, then quantizing and validating that model.

## Safe integration plan

1. **Choose an actual source checkpoint.** Record its exact model ID/revision, license, architecture, tokenizer, tensor shapes, and SHA-256. Do not treat the static model specification as a checkpoint.
2. **Choose a supported quantizer/runtime.** Use a model-format-specific tool that can read the source architecture and emit a documented deployment artifact. Record quantizer version, method, calibration corpus, and output format. The schema package is not that tool.
3. **Preserve the original checkpoint.** Quantize into a separate output directory. Never overwrite the source weights.
4. **Validate tensor decoding with schema-review where applicable.** Supply already-decoded tensor payloads plus exact shape/scale/zero-point/axis or ternary codebook/bit-order metadata to `schema_review.execute_and_validate`. Treat its report as a numeric transform check only. Do not claim it has discovered or preserved metadata from the original ONNX graph unless a separately verified extractor supplies that evidence.
5. **Run independent model-level tests.** Compare the quantized model against the original in the actual inference runtime using a fixed evaluation corpus. Record task-quality metrics, output regressions, latency, peak resident memory, GPU/CPU memory, and context-length behavior. Reject the artifact if the declared acceptance thresholds fail.
6. **Deploy through StackAlign's configured model endpoint.** Keep model weights in a separately managed inference runtime and configure StackAlign to call its OpenAI-compatible endpoint. Do not copy hundreds of gigabytes of weights into the StackAlign source repository or silently install a model on a production host.

## Required artifact manifest

A deployable candidate should carry a machine-readable manifest containing at least:

- source model identity, revision, license, and source hash;
- output artifact format, quantization method, bit width, and artifact hash;
- total parameter count and measured artifact bytes;
- quantizer and inference-runtime versions;
- calibration/evaluation corpus identifiers and hashes;
- per-model quality metrics and explicit acceptance thresholds;
- measured peak host RAM, VRAM, KV-cache use, and tested context length;
- schema-review version and per-tensor validation report references, when used;
- known unsupported operators, tensor types, and runtime limitations.

A candidate is **not deployable** while any required field is unknown or while model-level parity/quality validation is missing.

## StackAlign deployment boundary

StackAlign's planner is a constrained request planner, not a model server. It should send a bounded request to a configured inference endpoint, validate the returned plan, and retain deterministic execution authority locally. The model must not receive shell, root, Docker, database, or host-filesystem authority. No model installation, package change, service change, firewall change, or production-host mutation is authorized by this document.

## Current conclusion

- **Can schema-review shrink the current model? No.** Its current transforms decode/expand quantized payloads; they do not quantize a checkpoint.
- **Can it help validate a future quantization pipeline? Yes, narrowly.** It can validate specified FLOAT16, INT8, and two-bit ternary decoded-payload transforms against its independent standard-library references, subject to the documented metadata and model-level validation limits.
- **Can the specified 550–760B model fit an ordinary single server by setting active parameters to 8B? No.** The total stored weights remain the governing weight-storage problem.
- **Practical route:** select or distill a genuine 1–8B-class checkpoint, quantize it with a compatible model quantizer, benchmark it, and connect StackAlign to the separately hosted inference endpoint.

No checkpoint was downloaded, no model was quantized, no host was changed, and no inference service was started as part of this work.
