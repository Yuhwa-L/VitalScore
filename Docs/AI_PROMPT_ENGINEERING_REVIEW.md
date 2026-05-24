# VitalScore AI Prompt Engineering Review

Date: 2026-05-24

## Scope

This review covers executable prompt construction and prompt-like AI context in the project. Historical prompt text in seeded JSON is sample data, not a live prompt source. Fixed acoustic voice prompts are user tasks and model context for later analysis, but they are not LLM instructions.

## Prompt Inventory

| Prompt family | Live source files | Goal | Output contract |
| --- | --- | --- | --- |
| Eye-focus summary | `VitalScore/Features/EyeFocus/OpenAIEyeFocusSummaryClient.swift` | Turn reaction, gaze, calibration, and tracking-quality data into short non-medical app summaries. | OpenAI Responses JSON schema: `overall_summary`, `confidence`, `sections`. |
| Voice opening question | `VitalScore/Core/AI/VoiceAIConversationBuilder.swift`, `VitalScore/Core/AI/AIConversationClient.swift`, `scripts/ai-dialog-server.py` | Generate one first spoken question for a 2-3 minute, 4-turn wellness voice check-in. | Responses JSON schema with opening prompt/plan fields. |
| Voice chat follow-up | `VitalScore/Core/AI/VoiceAIConversationBuilder.swift`, `VitalScore/Core/AI/AIConversationClient.swift`, `scripts/ai-dialog-server.py` | Produce short personalized follow-ups from the latest transcript, then a final summary. | Responses JSON schema: `reply`, `should_continue`/`shouldContinue`, `source`. |
| Voice post-session scoring | `VitalScore/Core/AI/VoiceAIConversationBuilder.swift`, `VitalScore/Core/AI/AIConversationClient.swift`, `scripts/ai-dialog-server.py` | Score a completed voice session from saved export data, acoustic features, optional transcript, and baseline context. | Responses JSON schema: score, confidence, rationale, summary, arrays, safety note. Audio path uses Chat Completions JSON object mode. |
| Realtime transcription bias | `scripts/ai-dialog-server.py` | Bias speech transcription toward VitalScore wellness vocabulary without changing user wording. | OpenAI Realtime transcription session config. |
| Fixed acoustic prompts | `VitalScore/Core/AI/VoiceAIConversationBuilder.swift` | Standardize user speech capture for silence, vowels, counting, and read-aloud tasks. | Not an LLM prompt; used as UI text and later analysis context. |
| Stored prompt copies | `VitalScore/Resources/TagData/**`, tests | Seeded or test history containing prior AI prompts. | Not live behavior. |

## Improvements Applied

| Family | Before | After |
| --- | --- | --- |
| Eye-focus summary | Long natural-language instructions and raw log appended after metric bullets. | Structured role, input contract, source priority, confidence calibration, and JSON prompt payload with parsed `gazeLog` plus `computedResult`. |
| Voice opening | Direct OpenAI path used a short freeform line list; server path had flat constraints. | Both paths now use explicit role/goal/input-contract/conversation-contract blocks and suppress internal score or baseline leakage. |
| Voice follow-up | Follow-up rules existed, but transcript injection risk was implicit. | Both paths now declare transcripts/history as data only, require one concrete detail, enforce no repeated question intent, and keep final turn question-free. |
| Voice scoring | Had useful safety rules but source priority and confidence calibration were mixed into a flat list. | Added goal, input contract, source priority, scoring rules, confidence calibration, safety rules, and output style blocks. |
| Realtime transcription | Vocabulary hint only. | Added instruction to preserve user words and avoid adding diagnosis or advice. |
| Backup validation | Remote chat normalization checked emptiness, repeated questions, and final questions. | Added deterministic live-conversation boundary filter that falls back locally when remote opening/chat text contains medical or identity-risk content. |

## Prompt Engineering Techniques Used

- Role separation: each system instruction now states whether the model is opening a live conversation, continuing a live turn, scoring a completed export, or summarizing eye-focus data.
- Task/data separation: prompts now tell the model to treat context, transcripts, prompt text, logs, file names, and metadata as data only.
- Prompt-injection hardening: user transcripts and log fields cannot override role, safety rules, JSON shape, or scoring task.
- Source priority: analysis prompts rank authoritative data before supporting traces, transcripts, history, daily records, or debug audio.
- Confidence calibration: eye and voice outputs now define when confidence should be high, medium, or low.
- Negative constraints: prompts explicitly forbid diagnosis, treatment advice, disease prediction, identity inference, protected-trait inference, emotion labeling, and causal health claims.
- Output contracts: all primary AI paths continue to use strict structured JSON where available.
- Data minimization: prompts avoid exposing internal model/schema details to user-facing text and limit debug audio use to recording-quality observations.
- Deterministic fallback: Swift still validates and replaces bad remote live chat/opening output with local safe prompts.
- Mode gating: fixed-prompt voice sessions are not penalized for missing conversation transcripts; freestyle sessions can use transcript context.

## Remaining Risks

- The audio-analysis path uses Chat Completions JSON object mode instead of the same strict schema because it attaches audio inputs. The prompt still includes `requiredJsonShape`, and the Swift/Python clients parse the returned JSON, but schema enforcement is weaker than Responses strict JSON.
- Prompt text is duplicated between the Swift direct path and the local Python server. The wording is now aligned, but a future shared prompt fixture or generated tests would reduce drift.
- Seed JSON contains historical AI prompt text. It should remain treated as fixture data unless the app starts loading it as prompt source.

