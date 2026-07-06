# NEO-LAB

## Deterministic Local Cognitive Control Plane

**NEO-LAB** is a local, deterministic control plane for orchestrating multiple locally hosted large language models (LLMs) as role-separated inference engines under explicit governance, bounded memory, and fully inspectable state.

NEO-LAB is designed as a professional engineering lab assistant, not an autonomous agent.

All execution is local. All state is explicit. All behavior is deterministic.

---

## System Overview

NEO-LAB implements a control-plane architecture for AI inference rather than a traditional chatbot interface. It treats LLMs as stateless, interchangeable compute engines governed by a stateful, deterministic controller.

The system prioritizes:

- Predictability over emergence
- Inspectability over opacity
- Governance over autonomy

## What NEO-LAB Is

- A **deterministic router** (rule-based intent → model selection)
- A **governed control plane** (explicit state, modes, and contracts)
- A **file-driven IPC system** (atomic, concurrency-safe)
- A **local-first AI system** (offline-capable, no cloud dependency)
- A **single-response generator** for summaries, detailed explanations, and multi-page reports

NEO-LAB is **not**:

- An autonomous agent
- A self-modifying system
- A tool-execution framework
- A blended or ensemble model
- A cloud service

## Core Architecture (Atomic File-Based IPC)

NEO-LAB uses an atomic per-message file queue to eliminate race conditions and ensure deterministic execution.

```
queue_v2/
├─ inbox/                  # One JSON file per user message
├─ outbox/
│  └─ <message_id>/
│     ├─ status.json       # Execution phase, progress counters
│     └─ response.txt      # Streaming model output
└─ processed/              # Archived input messages
```

### Processing Flow

```
User
 ↓
neo_chat.ps1
 ↓  (atomic JSON message)
queue_v2/inbox/<id>.json
 ↓
neo_loop.ps1
 ├─ intent classification
 ├─ explicit state & persona loading
 ├─ deterministic model routing
 ├─ streaming inference
 └─ bounded memory update
 ↓
queue_v2/outbox/<id>/response.txt
```

Key properties: no message overwrites, safe concurrency, replayable execution, fully inspectable artifacts.

## Model Roles (One Active Model per Request)

Requests are routed deterministically; exactly one model is active per request.

| Cognitive Role | Model             |
| -------------- | ----------------- |
| Chat / Persona | dolphin-llama3    |
| Code           | deepseek-coder-v2 |
| Analysis       | deepseek-r1       |
| Vision         | qwen2.5-vl        |

Model availability is queried dynamically via Ollama. If a target model is unavailable, NEO-LAB fails closed or falls back safely.

## Output Modes

Supported one-shot modes:

- `/summary <topic>` — concise, complete response
- `/detail <topic>` — detailed technical explanation
- `/report <topic>` — single multi-page structured report

### Report Writer Mode

When enabled (`/reportmode on`), NEO-LAB enforces a strict output contract with required sections: Executive Summary; Scope & Assumptions; Core Analysis; Methods / Models / Math; Implementation; Risks, Limitations, Verification Checklist; References.

## Streaming Output & Progress Visibility

Output streams incrementally while models generate. Progress is written to `queue_v2/outbox/<id>/status.json`, including current execution phase, characters written, and streaming activity indicators.

## Memory System (Bounded & Inspectable)

Memory is JSON-based, explicitly bounded, stored on disk, and separated by intent:

```
queue/
├─ memory_chat.json
├─ memory_code.json
├─ memory_analysis.json
└─ memory_vision.json
```

No embeddings, no hidden vectors, no implicit recall. Memory can be inspected or cleared at any time.

## Governance & Safety Posture

- No autonomy
- No self-execution
- No self-modification
- No privilege escalation
- Human remains root authority

## Requirements

- Windows 10 / 11
- PowerShell 5.1
- Ollama (local inference server)

Recommended models: dolphin-llama3, deepseek-coder-v2, deepseek-r1, qwen2.5-vl.

## Quick Start

Terminal A (control loop):

```powershell
cd <repo-root>
.\neo_loop.ps1
```

Terminal B (chat client):

```powershell
cd <repo-root>
.\neo_chat.ps1
```

Example:

```
/report Write a multi-page engineering report explaining why atomic IPC queues prevent race conditions.
```

## QA Harness (Optional)

```powershell
powershell -ExecutionPolicy Bypass -File tests\qa\qa_harness.ps1
```

Results are written to `tests/qa/qa_results.json`.

## Roadmap

- Report size governor (short / normal / long)
- Live-tail streaming output in chat client
- Stronger output validation and regression tests
- Optional message integrity verification

## License

Dual-licensed: free for research and academic use; commercial use requires a paid license. See [LICENSE](LICENSE). Contact: darksciencedivision@gmail.com

## Disclaimer

NEO-LAB provides general informational output only. For legal, medical, or financial decisions, consult qualified professionals and primary sources.
