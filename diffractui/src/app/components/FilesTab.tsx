"use client";

import { useState, useEffect, useCallback, useRef } from "react";

interface DirItem {
  name: string;
  isDir: boolean;
  size: number;
  mtime: number;
}

const ROOT = "/sandbox";

export default function FilesTab({ sandboxName }: { sandboxName: string }) {
  const [path, setPath] = useState(ROOT);
  const [items, setItems] = useState<DirItem[]>([]);
  const [loading, setLoading] = useState(false);
  const [error, setError] = useState("");
  const [uploading, setUploading] = useState(false);
  const [dragging, setDragging] = useState(false);
  const fileInput = useRef<HTMLInputElement>(null);

  const load = useCallback(
    (p: string) => {
      setLoading(true);
      setError("");
      fetch(`/api/files?sandbox=${encodeURIComponent(sandboxName)}&path=${encodeURIComponent(p)}`)
        .then(async (r) => {
          const data = await r.json();
          if (!r.ok) throw new Error(data.error || "Failed to load");
          setItems(data.items || []);
          setPath(data.path || p);
        })
        .catch((e) => setError(e.message || "Failed to load"))
        .finally(() => setLoading(false));
    },
    [sandboxName],
  );

  useEffect(() => {
    load(ROOT);
  }, [load]);

  function navigate(item: DirItem) {
    if (item.isDir) load(joinPath(path, item.name));
  }

  async function upload(files: FileList | File[]) {
    const list = Array.from(files);
    if (list.length === 0) return;
    setUploading(true);
    setError("");
    try {
      for (const file of list) {
        const form = new FormData();
        form.append("file", file);
        const r = await fetch(
          `/api/files?sandbox=${encodeURIComponent(sandboxName)}&path=${encodeURIComponent(path)}`,
          { method: "POST", body: form },
        );
        const data = await r.json();
        if (!r.ok) throw new Error(data.error || `Upload of ${file.name} failed`);
      }
      load(path);
    } catch (e) {
      setError(e instanceof Error ? e.message : "Upload failed");
    } finally {
      setUploading(false);
      if (fileInput.current) fileInput.current.value = "";
    }
  }

  function remove(item: DirItem) {
    const full = joinPath(path, item.name);
    if (!confirm(`Delete "${item.name}"${item.isDir ? " and everything in it" : ""}? This is irreversible.`)) return;
    fetch(`/api/files?sandbox=${encodeURIComponent(sandboxName)}&path=${encodeURIComponent(full)}`, {
      method: "DELETE",
    })
      .then(async (r) => {
        const data = await r.json();
        if (!r.ok) throw new Error(data.error || "Delete failed");
        load(path);
      })
      .catch((e) => setError(e.message || "Delete failed"));
  }

  function downloadUrl(item: DirItem) {
    const full = joinPath(path, item.name);
    return `/api/files?sandbox=${encodeURIComponent(sandboxName)}&path=${encodeURIComponent(full)}&download=1`;
  }

  const crumbs = buildCrumbs(path);

  return (
    <div
      className="space-y-3"
      onDragOver={(e) => {
        e.preventDefault();
        setDragging(true);
      }}
      onDragLeave={(e) => {
        e.preventDefault();
        setDragging(false);
      }}
      onDrop={(e) => {
        e.preventDefault();
        setDragging(false);
        if (e.dataTransfer.files?.length) upload(e.dataTransfer.files);
      }}
    >
      {/* Toolbar: breadcrumbs + upload */}
      <div className="flex items-center justify-between gap-3">
        <div className="flex items-center gap-1 text-xs font-mono text-nc-text-muted min-w-0 flex-wrap">
          {crumbs.map((c, i) => (
            <span key={c.path} className="flex items-center gap-1">
              {i > 0 && <span className="text-nc-text-dim">/</span>}
              <button
                onClick={() => load(c.path)}
                className={`hover:text-nc-text transition-colors ${
                  i === crumbs.length - 1 ? "text-nc-text" : "text-nc-text-muted"
                }`}
              >
                {c.label}
              </button>
            </span>
          ))}
        </div>
        <div className="flex items-center gap-2 shrink-0">
          <button
            onClick={() => load(path)}
            className="px-2.5 py-1.5 rounded-md border border-nc-border text-xs text-nc-text-muted hover:text-nc-text hover:bg-nc-surface-hover transition-all"
          >
            Refresh
          </button>
          <button
            onClick={() => fileInput.current?.click()}
            disabled={uploading}
            className={`px-3 py-1.5 rounded-md text-xs font-medium transition-all ${
              uploading
                ? "bg-nc-border text-nc-text-dim cursor-wait"
                : "bg-nc-green text-black hover:bg-nc-green-dark"
            }`}
          >
            {uploading ? "Uploading..." : "Upload"}
          </button>
          <input
            ref={fileInput}
            type="file"
            multiple
            className="hidden"
            onChange={(e) => e.target.files && upload(e.target.files)}
          />
        </div>
      </div>

      {error && (
        <div className="px-3 py-2 rounded-md bg-nc-danger/10 border border-nc-danger/30 text-nc-danger text-xs">
          {error}
        </div>
      )}

      {/* Drop / list area */}
      <div
        className={`rounded-lg border min-h-[24rem] ${
          dragging ? "border-nc-green bg-nc-green/5" : "border-nc-border bg-nc-surface"
        } transition-colors`}
      >
        {/* Parent-dir row */}
        {path !== ROOT && (
          <button
            onClick={() => load(parentPath(path))}
            className="w-full flex items-center gap-2 px-4 py-2.5 text-sm text-nc-text-muted hover:bg-nc-surface-hover transition-colors border-b border-nc-border"
          >
            <FolderIcon /> <span className="font-mono">..</span>
          </button>
        )}

        {loading ? (
          <div className="p-6 text-center text-nc-text-dim text-sm">Loading...</div>
        ) : items.length === 0 ? (
          <div className="p-10 text-center text-nc-text-dim text-sm">
            {dragging ? "Drop files to upload" : "Empty folder — drag files here or click Upload"}
          </div>
        ) : (
          <div className="divide-y divide-nc-border">
            {items.map((item) => (
              <div
                key={item.name}
                className="flex items-center gap-3 px-4 py-2.5 hover:bg-nc-surface-hover transition-colors group"
              >
                <button
                  onClick={() => navigate(item)}
                  disabled={!item.isDir}
                  className={`flex items-center gap-2 min-w-0 flex-1 text-left ${
                    item.isDir ? "cursor-pointer" : "cursor-default"
                  }`}
                >
                  {item.isDir ? <FolderIcon /> : <FileIcon />}
                  <span
                    className={`text-sm font-mono truncate ${
                      item.isDir ? "text-nc-text group-hover:text-nc-green" : "text-nc-text-muted"
                    }`}
                  >
                    {item.name}
                  </span>
                </button>
                <span className="text-xs text-nc-text-dim shrink-0 w-20 text-right tabular-nums">
                  {item.isDir ? "—" : formatSize(item.size)}
                </span>
                <span className="text-xs text-nc-text-dim shrink-0 w-28 text-right hidden sm:block">
                  {formatTime(item.mtime)}
                </span>
                <div className="flex items-center gap-1 shrink-0 w-16 justify-end">
                  {!item.isDir && (
                    <a
                      href={downloadUrl(item)}
                      className="px-2 py-1 rounded text-xs text-nc-text-dim hover:text-nc-text hover:bg-nc-bg transition-all opacity-0 group-hover:opacity-100"
                      title="Download"
                    >
                      ↓
                    </a>
                  )}
                  <button
                    onClick={() => remove(item)}
                    className="px-2 py-1 rounded text-xs text-nc-text-dim hover:text-nc-danger hover:bg-nc-bg transition-all opacity-0 group-hover:opacity-100"
                    title="Delete"
                  >
                    ✕
                  </button>
                </div>
              </div>
            ))}
          </div>
        )}
      </div>

      <p className="text-xs text-nc-text-dim">
        Files here live in the agent&apos;s working directory ({ROOT}). Anything you upload is
        immediately available to the agent.
      </p>
    </div>
  );
}

// ── helpers ───────────────────────────────────────────────────────────────
function joinPath(base: string, name: string): string {
  return base.endsWith("/") ? base + name : base + "/" + name;
}

function parentPath(p: string): string {
  if (p === ROOT) return ROOT;
  const idx = p.lastIndexOf("/");
  const parent = idx <= 0 ? "/" : p.slice(0, idx);
  return parent.length < ROOT.length ? ROOT : parent;
}

function buildCrumbs(p: string): { label: string; path: string }[] {
  const crumbs = [{ label: "sandbox", path: ROOT }];
  if (p === ROOT) return crumbs;
  const rest = p.slice(ROOT.length + 1).split("/").filter(Boolean);
  let acc = ROOT;
  for (const seg of rest) {
    acc = acc + "/" + seg;
    crumbs.push({ label: seg, path: acc });
  }
  return crumbs;
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes} B`;
  if (bytes < 1024 * 1024) return `${(bytes / 1024).toFixed(1)} KB`;
  if (bytes < 1024 * 1024 * 1024) return `${(bytes / 1024 / 1024).toFixed(1)} MB`;
  return `${(bytes / 1024 / 1024 / 1024).toFixed(1)} GB`;
}

function formatTime(unix: number): string {
  if (!unix) return "—";
  try {
    return new Date(unix * 1000).toLocaleDateString(undefined, {
      month: "short",
      day: "numeric",
      hour: "2-digit",
      minute: "2-digit",
    });
  } catch {
    return "—";
  }
}

function FolderIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" className="shrink-0 text-nc-green">
      <path
        d="M3 7a2 2 0 0 1 2-2h4l2 2h8a2 2 0 0 1 2 2v8a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V7Z"
        stroke="currentColor"
        strokeWidth="1.5"
      />
    </svg>
  );
}

function FileIcon() {
  return (
    <svg width="15" height="15" viewBox="0 0 24 24" fill="none" className="shrink-0 text-nc-text-dim">
      <path
        d="M6 3h7l5 5v13a1 1 0 0 1-1 1H6a1 1 0 0 1-1-1V4a1 1 0 0 1 1-1Z"
        stroke="currentColor"
        strokeWidth="1.5"
      />
      <path d="M13 3v5h5" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  );
}
