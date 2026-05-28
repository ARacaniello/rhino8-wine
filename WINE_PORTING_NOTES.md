# Rhino 8 on Linux via Wine — Porting Notes

Detailed writeup of every problem encountered getting Rhinoceros 8 running under Wine 11.9. For setup instructions see [README.md](README.md).

---

## What Was Changed and Why

### Problem 1: Immediate Crash — Stack Overflow

**Symptom:** Rhino crashed on startup before showing any UI. Wine logged a STATUS_STACK_OVERFLOW exception.

**Root cause:** .NET 8's CLR calibrates its maximum safe recursion depth by querying the stack size via `VirtualQuery`. It reads `AllocationBase` from the stack's memory region to calculate available depth. Wine's default thread stacks are 1MB, but .NET 8 has a minimum requirement of ~512MB of *reserved* stack space to function at all.

**Fix 1 — Force 512MB stack** (`dlls/ntdll/unix/thread.c` → `init_thread_stack`):

Force every thread's stack to reserve and commit 512MB. This gives .NET enough room to start.

```c
if (reserve_size < 512 * 1024 * 1024) reserve_size = 512 * 1024 * 1024;
if (commit_size < reserve_size) commit_size = reserve_size;
```

**Fix 2 — Clamp the reported stack size** (`dlls/ntdll/unix/virtual.c` → `fill_basic_memory_info`):

Even with 512MB reserved, .NET saw the full 512MB via `VirtualQuery` and tried to use all of it for recursion depth calibration — then blew through the guard page. Clamp `AllocationBase` so `VirtualQuery` reports only 1MB of usable stack. .NET calibrates to 1MB depth while still having 512MB physically available.

```c
char *clamped = (char *)teb->Tib.StackBase - (1 * 1024 * 1024);
if (clamped > (char *)teb->DeallocationStack &&
    (char *)info->AllocationBase <= (char *)teb->DeallocationStack + host_page_size)
    info->AllocationBase = clamped;
```

**Fix 3 — Move the guard page** (`dlls/ntdll/unix/virtual.c` → `virtual_alloc_thread_stack`):

With 512MB stacks, the guard page was at `DeallocationStack + 4KB`. When a stack overflow exception fires, Windows needs to deliver an exception frame (3–8KB) in the "guaranteed region" below the guard. With only 4KB of guaranteed region, the exception frame itself caused a second fault, crashing Wine's signal handler. Move the guard page to `DeallocationStack + 64KB` for stacks ≥512MB.

```c
SIZE_T guard_offset = (view->size >= 512 * 1024 * 1024) ? 64 * 1024 : host_page_size;
```

---

### Problem 2: Infinite Recursion Filling the 512MB Stack

**Symptom:** Rhino still crashed, but now the crash was deep inside `pf_vsnprintf_a` (Wine's printf). The full 512MB stack was consumed. Examining the stack showed the same return address (`wine_dbg_log+0x21`) repeating every 264 bytes — a tight infinite loop.

**Root cause:** A `WARN()` call inside `fill_basic_memory_info` (to log when the clamp was applied) caused infinite recursion. Wine's `WARN()` calls `wine_dbg_log()` → `wine_dbg_vprintf()` → `vsnprintf`, and somewhere in that chain a `VirtualQuery` call was made (from .NET's signal handlers or mono's glibc wrappers). This re-entered `fill_basic_memory_info`, which called `WARN()` again.

**Fix:** Removed all `WARN()`/`ERR()` logging from `fill_basic_memory_info` and `init_thread_stack`. These functions are in the hot path called constantly by .NET — they cannot log anything.

---

### Problem 3: Dark Mode Mutual Recursion — 254,955 Frames Deep

**Symptom:** Rhino crashed with a stack trace showing Rhino's own code: `Rhino.Runtime.AdvancedSettings.get_DarkMode()` (C#) calling P/Invoke to `RHC_RhOSInDarkMode` in `rhcommon_c.dll`, which called back into .NET managed code, which called `get_DarkMode()` again. 254,955 frames deep.

**Root cause:** On Windows, `RHC_RhOSInDarkMode` detects the dark mode setting via Windows APIs that don't exist on Wine. Wine's stub returns something that caused the function to re-invoke the managed callback instead of returning a result.

**Fix:** Binary-patched `rhcommon_c.dll`. The export `RHC_RhOSInDarkMode` at file offset `0xdff50` (RVA `0xe0b50`) was a JMP thunk:

```
before: 48 ff 25 19 8d 08 00 cc   (JMP [rip+...])
after:  31 c0 c3 90 90 90 90 cc   (xor eax,eax; ret; nop*4)
```

Always returns 0 (light mode), breaking the recursion. Back up the DLL before patching.

---

### Problem 4: Diagnostic Kill Limits Cutting Rhino's Throat

**Symptom:** Rhino showed a licensing dialog, but every licensing attempt returned "evaluation period expired."

**Root cause (self-inflicted):** For debugging, kill-limit counters had been added to `dispatch_exception` and `call_seh_handlers`. Rhino's .NET runtime fires hundreds of internal CLR exceptions (`e0434352`) during normal startup — completely normal. Rhino was being killed after 100 exceptions before it ever finished initializing.

**Fix:** Completely removed the diagnostic counters. Both functions were reverted to upstream.

---

### Problem 5: No X11 Display

**Symptom:** Rhino exited silently with "no driver could be loaded."

**Root cause:** The `DISPLAY` environment variable wasn't set.

**Fix:** Added `DISPLAY="${DISPLAY:-:0}"` to the launch script.

---

### Problem 6: Licensing — Port 1717 Never Bound

**Symptom:** The OAuth login flow opened Firefox. After logging in to McNeel's servers, Firefox redirected to `http://127.0.0.1:1717/` to deliver the auth token — and got "Firefox can't connect to the server."

**Investigation:** Enabled `WINEDEBUG=+http` and confirmed Rhino was correctly calling `HttpAddUrlToUrlGroup` with `http://127.0.0.1:1717/`. Wine has a real implementation of the Windows HTTP Server API: `httpapi.dll` → `IOCTL_HTTP_ADD_URL` → `http.sys` kernel driver in `winedevice.exe`. Added instrumentation to Wine's `http_add_url` confirming the ioctl reached the driver and `bind()`/`listen()` was being attempted — but the socket never appeared.

**Root cause:** Stale `http.sys` state. Between Rhino restarts, only Rhino was being killed while the wineserver (and the `winedevice.exe` running `http.sys`) stayed alive. The old `http.sys` retained state from the previous run that interfered with the new run's port binding.

**Fix:** Kill the wineserver completely before launching (`wineserver -k`). This terminates the old `http.sys` winedevice. When Rhino launches fresh, a new `http.sys` starts with clean state, port 1717 binds, and the OAuth callback completes. The `--fresh` flag in `run-rhino.sh` does this automatically.

---

## Summary of Source Changes

| File | Change |
|------|--------|
| `dlls/ntdll/unix/thread.c` | Force 512MB reserve+commit per thread; clamp TEB.StackLimit to StackBase−1MB |
| `dlls/ntdll/unix/virtual.c` | Clamp VirtualQuery AllocationBase for stack queries (no logging); move guard page to +64KB for stacks ≥512MB |
| `dlls/wintrust/wintrust_main.c` | Override Authenticode result to S_OK (Wine lacks MS CA root store needed to verify Microsoft signatures) |

All changes are in `rhino8-wine.patch`.
