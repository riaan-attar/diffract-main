/**
 * ChatPage — a normal message-bubble chat with the Diffract agent.
 *
 * Talks to the agent's OpenAI-compatible gateway (`/v1/chat/completions`,
 * proxied by Caddy to the in-sandbox gateway on :8642) with Server-Sent-Event
 * streaming. The gateway runs the full agent (tools, skills, the Diffract SOUL
 * identity) — this is just a friendly chat surface over it, replacing the older
 * embedded terminal (TUI). Conversation history is kept client-side and resent
 * each turn (the endpoint is stateless per request, OpenAI-style).
 *
 * Rendered persistently by App.tsx (see the chat host block) so the
 * conversation survives tab switches; `isActive` only drives input focus.
 */
import { ArrowUp, Plus, Square } from "lucide-react";
import { useCallback, useEffect, useRef, useState } from "react";

import { cn } from "@/lib/utils";

type Role = "user" | "assistant";
interface ChatMessage {
  role: Role;
  content: string;
}

// Caddy routes origin /v1/* -> the sandbox gateway (:8642). Leading slash keeps
// it at the origin root (NOT under the dashboard's /agent base path).
const CHAT_COMPLETIONS_URL = "/v1/chat/completions";
const MODEL = "hermes-agent";

const GREETING =
  "Hi, I'm Diffract Agent — running safely for your business. How can I help?";

export default function ChatPage({ isActive = true }: { isActive?: boolean }) {
  const [messages, setMessages] = useState<ChatMessage[]>([]);
  const [input, setInput] = useState("");
  const [streaming, setStreaming] = useState(false);
  const [error, setError] = useState<string | null>(null);

  const scrollRef = useRef<HTMLDivElement | null>(null);
  const inputRef = useRef<HTMLTextAreaElement | null>(null);
  const abortRef = useRef<AbortController | null>(null);

  // Keep the latest message in view as content streams in.
  useEffect(() => {
    const el = scrollRef.current;
    if (el) el.scrollTop = el.scrollHeight;
  }, [messages, streaming]);

  // Focus the composer when the chat tab becomes active.
  useEffect(() => {
    if (isActive) inputRef.current?.focus();
  }, [isActive]);

  const send = useCallback(async () => {
    const text = input.trim();
    if (!text || streaming) return;

    setError(null);
    setInput("");
    const history: ChatMessage[] = [...messages, { role: "user", content: text }];
    // Append an empty assistant message we fill as deltas arrive.
    setMessages([...history, { role: "assistant", content: "" }]);
    setStreaming(true);

    const ac = new AbortController();
    abortRef.current = ac;

    try {
      const res = await fetch(CHAT_COMPLETIONS_URL, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          model: MODEL,
          stream: true,
          messages: history.map((m) => ({ role: m.role, content: m.content })),
        }),
        signal: ac.signal,
      });
      if (!res.ok || !res.body) {
        throw new Error(`Request failed (HTTP ${res.status})`);
      }

      const reader = res.body.getReader();
      const decoder = new TextDecoder();
      let buf = "";
      let acc = "";

      for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        buf += decoder.decode(value, { stream: true });
        const lines = buf.split("\n");
        buf = lines.pop() ?? ""; // keep the trailing partial line
        for (const raw of lines) {
          const line = raw.trim();
          if (!line.startsWith("data:")) continue;
          const payload = line.slice(5).trim();
          if (!payload || payload === "[DONE]") continue;
          try {
            const json = JSON.parse(payload);
            const delta = json?.choices?.[0]?.delta?.content;
            if (typeof delta === "string" && delta.length > 0) {
              acc += delta;
              setMessages((prev) => {
                const next = prev.slice();
                next[next.length - 1] = { role: "assistant", content: acc };
                return next;
              });
            }
          } catch {
            // ignore keep-alives / non-JSON / partial frames
          }
        }
      }

      if (!acc) {
        setMessages((prev) => {
          const next = prev.slice();
          next[next.length - 1] = {
            role: "assistant",
            content: "(no response)",
          };
          return next;
        });
      }
    } catch (e) {
      const aborted = e instanceof DOMException && e.name === "AbortError";
      if (!aborted) {
        setError(
          e instanceof Error ? e.message : "Something went wrong. Please try again.",
        );
        // Drop the empty assistant placeholder if nothing streamed.
        setMessages((prev) => {
          const next = prev.slice();
          const last = next[next.length - 1];
          if (last && last.role === "assistant" && !last.content) next.pop();
          return next;
        });
      }
    } finally {
      setStreaming(false);
      abortRef.current = null;
      if (isActive) inputRef.current?.focus();
    }
  }, [input, streaming, messages, isActive]);

  const stop = useCallback(() => abortRef.current?.abort(), []);

  const newChat = useCallback(() => {
    abortRef.current?.abort();
    setMessages([]);
    setInput("");
    setError(null);
    inputRef.current?.focus();
  }, []);

  return (
    <div className="flex h-full min-h-0 flex-1 flex-col">
      {/* Toolbar */}
      <div className="flex items-center justify-between border-b border-white/10 px-4 py-2.5">
        <span className="text-sm font-medium text-text-primary">Diffract Agent</span>
        <button
          type="button"
          onClick={newChat}
          className="inline-flex items-center gap-1.5 rounded-lg border border-white/15 px-2.5 py-1.5 text-xs text-text-secondary transition-colors hover:border-white/30 hover:text-text-primary"
        >
          <Plus className="h-3.5 w-3.5" /> New chat
        </button>
      </div>

      {/* Messages */}
      <div ref={scrollRef} className="min-h-0 flex-1 overflow-y-auto px-4 py-6">
        <div className="mx-auto flex w-full max-w-3xl flex-col gap-4">
          {messages.length === 0 && (
            <div className="mt-12 text-center">
              <p className="text-base text-text-primary">{GREETING}</p>
              <p className="mt-2 text-sm text-text-tertiary">
                Ask a question or describe a task to get started.
              </p>
            </div>
          )}

          {messages.map((m, i) => (
            <div
              key={i}
              className={cn(
                "flex",
                m.role === "user" ? "justify-end" : "justify-start",
              )}
            >
              <div
                className={cn(
                  "max-w-[85%] whitespace-pre-wrap break-words rounded-2xl px-4 py-2.5 text-sm leading-relaxed text-text-primary",
                  m.role === "user"
                    ? "bg-white/10"
                    : "border border-white/10 bg-white/[0.04]",
                )}
              >
                {m.content ||
                  (streaming && i === messages.length - 1 ? (
                    <span className="text-text-tertiary">…</span>
                  ) : (
                    ""
                  ))}
              </div>
            </div>
          ))}

          {error && (
            <div className="text-center text-sm text-red-400">{error}</div>
          )}
        </div>
      </div>

      {/* Composer */}
      <div className="border-t border-white/10 px-4 py-3">
        <div className="mx-auto flex w-full max-w-3xl items-end gap-2">
          <textarea
            ref={inputRef}
            value={input}
            onChange={(e) => setInput(e.target.value)}
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                void send();
              }
            }}
            rows={1}
            placeholder="Message Diffract Agent…"
            className="max-h-40 min-h-[2.75rem] flex-1 resize-none rounded-xl border border-white/10 bg-white/5 px-3.5 py-2.5 text-sm text-text-primary placeholder:text-text-tertiary focus:border-midground focus:outline-none"
          />
          {streaming ? (
            <button
              type="button"
              onClick={stop}
              aria-label="Stop"
              className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl border border-white/15 text-text-secondary transition-colors hover:text-text-primary"
            >
              <Square className="h-4 w-4" />
            </button>
          ) : (
            <button
              type="button"
              onClick={() => void send()}
              disabled={!input.trim()}
              aria-label="Send"
              className="inline-flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-midground text-background transition-opacity hover:opacity-90 disabled:cursor-not-allowed disabled:opacity-40"
            >
              <ArrowUp className="h-4 w-4" />
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
