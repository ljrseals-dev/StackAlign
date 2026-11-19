# Self-hosted LLM runtime

**Status: local Ollama integration implemented; runtime installation and live-host validation remain operator-controlled.**

StackAlign can discover a local Ollama runtime, inspect its model inventory, and request a model pull. It does not install Ollama, enable a system service, open a port, configure a firewall, or expose the inference API to the network.

## 1. Install and start the runtime

Install Ollama using its official installation instructions for your operating system. Review installer and package provenance yourself. Start the Ollama service using the method appropriate for your host. StackAlign deliberately does not run a remote installer or change system services.

```sh
export STACKALIGN_OLLAMA_HOST=http://127.0.0.1:11434
stackalign llm status
stackalign llm models
```

StackAlign rejects non-loopback HTTP endpoints for runtime management. Keep Ollama bound to loopback unless you separately design and secure a remote inference gateway.

## 2. Download a model

Choose a model and tag compatible with your machine's RAM/VRAM budget and license. Pulling downloads model data and can consume substantial disk space.

```sh
stackalign llm pull llama3.2:3b
# Review the plan; this performs no network request.
stackalign llm pull llama3.2:3b --apply
stackalign llm configure llama3.2:3b
# Review the local planner configuration plan.
stackalign llm configure llama3.2:3b --apply
```

The command validates the model identifier and invokes the installed `ollama pull` only when `--apply` is explicit. It does not select a model on the operator's behalf or claim a model will fit available hardware.

## 3. Connect StackAlign's planner

Ollama exposes an OpenAI-compatible endpoint. Point the existing constrained planner at it:

```sh
stackalign agent plan "Check whether my web server is healthy"
```

The planner continues to validate model output against StackAlign's strict schema. It remains a proposal-only interface: the model cannot execute shell commands or perform host mutations.

## 4. Commands and boundaries

- `stackalign llm status`: checks the loopback Ollama API and validates the model-list response.
- `stackalign llm models`: delegates read-only inventory to `ollama list`.
- `stackalign llm pull MODEL`: displays a plan.
- `stackalign llm pull MODEL --apply`: explicitly downloads the selected model.
- `stackalign llm configure MODEL`: displays a plan for saving the local planner endpoint and model.
- `stackalign llm configure MODEL --apply`: writes a mode-600, non-secret config file under `~/.config/stackalign/llm.env`; existing files are never overwritten.

Not included: Ollama installation, service enablement, GPU driver setup, model quantization, model conversion through schema/Cmajor, remote exposure, automatic model selection, or production sizing guarantees. Those require separate implementation and host-specific validation.

No model is bundled in this repository. No server is changed by the test suite.
