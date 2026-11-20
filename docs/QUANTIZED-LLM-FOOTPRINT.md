# Quantized LLM footprint and StackAlign deployment boundary

**Status: engineering assessment. No model artifact is included or deployed by this change.**

This document evaluates the ONNX-to-Cmajor emitter in `ljrseals-dev/schema`, including the merged ONNX patch and modified emitter script, as a possible route to reducing the model footprint used by StackAlign.

## Corrected repository finding

The schema repository does contain an ONNX-to-Cmajor conversion path. PRs #7 and #8 added the repository-local emitter at `tools/onnx/onnxToCmajor.py`, a Cmajor patch template, fallback rewrite logic, focused synthetic ONNX tests, requirements, documentation, and CI coverage. PR #8's main-branch merge commit is `fce779ea30a098794e298e39ae3fd8c96e80bd85`. This is more than the package-level tensor decoder alone; the earlier description that schema had no ONNX reader or Cmajor emitter was incorrect.

The converter loads and checks an ONNX model, applies supported initializer rewrites, performs shape inference and ONNX validation, inventories a deliberately limited operator set, and emits Cmajor source/patch files. It is a repository-local modified copy of the Cmajor Toolkit emitter, not an upstream-accepted Cmajor change.

## What the emitter currently does with quantized weights

The current fallback support is deliberately narrow:

- **FLOAT16:** finite FLOAT16 initializers and FLOAT16 Constant tensor attributes are promoted to FLOAT32. FLOAT16 graph inputs/outputs are rejected because an explicit runtime cast adapter is not implemented.
- **INT8:** signed INT8 initializer weights are folded through an initializer-backed ONNX `DequantizeLinear` node into FLOAT32 weights. Scale and optional zero point must be initializers; scalar or one-dimensional scale layouts are supported. Dynamic scales, UINT8, graph-boundary quantization, ambiguous consumers, and unsupported layouts are rejected.
- **Ternary:** UINT8 initializers are decoded from explicitly annotated packed two-bit ternary codes using the declared logical shape, bit order, and codebook. Missing/ambiguous metadata, reserved symbols, invalid padding, or malformed payloads are rejected.
- **Other quantized forms:** rejected rather than guessed.

**Critical size implication:** these fallbacks decode/promote the compressed values into FLOAT32 initializers before Cmajor emission. They are compatibility/lowering fallbacks, not a compact-weight-preserving quantizer. FLOAT16 becomes 32-bit storage; INT8 becomes 32-bit values; packed two-bit ternary becomes 32-bit values. Consequently, this current path does not itself reduce the emitted model's weight storage and may expand it substantially. It can make certain quantized ONNX tensors consumable by the existing emitter, but that is different from keeping weights compressed at inference time.

## Cmajor operator coverage and model suitability

The emitter's operator endpoint table is small: Tanh, Reshape, MatMul, Gemm, Add, Unsqueeze, Squeeze, Conv, GRU, Pad, Transpose, Constant, LSTM, Slice, Gather, and Concat. The script rejects operators outside that allowlist before code generation.

A modern transformer LLM normally needs operators and semantics beyond this list, commonly including Softmax, normalization (LayerNorm/RMSNorm), rotary-position operations, attention/cache handling, embedding/gather variants, and model-specific fused operators. Those are not made supported merely because MatMul and Add are present. Therefore the current emitter cannot be assumed to convert the proposed 550–760B MoE LLM. It needs a real model-specific ONNX export, an operator coverage report, graph/shape validation, Cmajor compilation, and runtime parity before suitability can be established.

The focused tests in `tools/onnx/test_fallback.py` exercise synthetic initializer rewrite and refusal cases. The PR descriptions and README explicitly do not claim Cmajor compilation, complete operator semantic parity, ONNX Runtime parity, or audio/model quality validation. Those remain separate acceptance gates.

## Storage estimates

The model specification describes 550–760 billion total parameters, with approximately 8B active during prefill and 16B during decode. Active parameters are not the same as stored parameters: the expert weights still need to be available to the runtime.

Raw weight storage lower bounds, using decimal GB/TB and excluding scales, metadata, alignment, tokenizer, runtime, KV cache, and allocator overhead:

| Representation retained at runtime | Bytes per parameter | 550B parameters | 760B parameters |
|---|---:|---:|---:|
| BF16 / FP16 | 2 | 1.10 TB | 1.52 TB |
| INT8 | 1 | 550 GB | 760 GB |
| packed 2-bit | 0.25 | 137.5 GB | 190 GB |
| FLOAT32 emitted by current schema fallback | 4 | 2.20 TB | 3.04 TB |

These are arithmetic lower bounds, not measured artifact sizes. The final row illustrates why decoding into FLOAT32 is not a compression path.

For comparison, a genuine dense 8B model retained as INT8 would require about 8 GB of raw weights; 4-bit would be about 4 GB. The schema emitter does not currently preserve a 4-bit representation. These figures still exclude runtime memory and context/KV cache.

## What would actually reduce StackAlign's model footprint

There are two distinct engineering paths:

1. **Use an already-small checkpoint.** Select a real 1–8B-class model with a compatible inference runtime and supported quantization format. Quantize it with a model-specific quantizer, measure the resulting artifact, and connect StackAlign's constrained planner to that runtime's OpenAI-compatible endpoint.
2. **Extend the schema/Cmajor path for compact inference.** Add quantized storage types and Cmajor operations that consume packed INT8/ternary weights directly without expanding them into FLOAT32 arrays. This requires verified Cmajor type/layout support or explicit packed-byte kernels, correct scale/zero-point/codebook handling, and operator lowering for the target model. It is a substantial compiler/runtime project, not just an emitter flag.

Do not claim path 2 is available until the generated Cmajor patch demonstrably retains the compressed representation and executes it correctly.

## Required validation before deployment

1. Identify the exact ONNX source checkpoint, revision, license, architecture, tokenizer, and SHA-256. The `shadowy-spooky-poltergeist` repository is a static specification/manual, not the checkpoint.
2. Run the emitter on a copy of the actual ONNX file. Capture the exact refusal or generated output; do not infer compatibility from model family or parameter count.
3. Record source ONNX bytes, emitted Cmajor source/patch bytes, initializer dtypes and byte counts before/after conversion, and generated artifact hashes.
4. Compile with a pinned Cmajor toolchain. Record compiler version, command, stdout/stderr, and exit status.
5. Execute the converted model and compare against the original ONNX Runtime outputs using fixed prompts/inputs and a reproducible evaluation corpus.
6. Measure task quality, latency, peak RAM/VRAM, KV-cache use, tested context length, and actual on-disk artifact size.
7. Reject the candidate if any required operator is unsupported, compilation fails, runtime parity/quality misses its predeclared threshold, or measured resource use exceeds the target server budget.

A deployable manifest should record source and output hashes, model/license/revision, quantizer/emitter/compiler/runtime versions, quantization scheme, operator coverage, evaluation corpus, numerical/task metrics, resource measurements, and all known limitations.

## StackAlign integration boundary

StackAlign's LLM planner is a constrained client, not an inference server. It sends a bounded planning request to an operator-configured OpenAI-compatible endpoint and validates the response locally. Model output does not receive shell, root, Docker, database, or host-filesystem authority.

Keep model weights in a separately managed inference runtime; do not commit them to StackAlign or silently install them on a production host. No package, service, firewall, production-host, or provider-egress changes are authorized by this documentation PR.

## Current conclusion

- The schema repository **does have** the ONNX-to-Cmajor emitter and the merged FLOAT16/INT8/ternary fallback patch. PR #7 and PR #8 are part of the current mainline.
- The existing fallback rewrites **expand quantized values to FLOAT32** before emission. They do not preserve compact weights and therefore do not currently reduce model storage.
- The emitter's limited operator set does not establish support for a modern transformer/MoE LLM.
- A real smaller deployment should begin with a genuine small checkpoint and an inference runtime that retains its quantized format. A direct schema/Cmajor route is a separate development track requiring packed-weight kernels, transformer operator coverage, compilation, and runtime parity.
- No checkpoint was downloaded, converted, compiled, benchmarked, or deployed. No server was changed.
