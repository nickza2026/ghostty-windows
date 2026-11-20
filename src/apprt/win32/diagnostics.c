/* Original localterm diagnostic bridge, from Microsoft's Process Snapshot API
 * and processsnapshot.h in Windows SDK 10.0.26100.0. Lifecycle smoke only.
 * Capture our own handle metadata: no VM clone, memory, names or other process.
 */
#define _WIN32_WINNT 0x0A00
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <processsnapshot.h>
#include <winternl.h>
#include <stdint.h>

DWORD localterm_win32_thread_handles(void (*emit)(uintptr_t, DWORD)) {
    HPSS snapshot = NULL;
    DWORD status = PssCaptureSnapshot(GetCurrentProcess(), PSS_CAPTURE_HANDLES,
                                    0, &snapshot);
    if (status != ERROR_SUCCESS) return status;

    HPSSWALK marker = NULL;
    status = PssWalkMarkerCreate(NULL, &marker);
    if (status == ERROR_SUCCESS) {
        PSS_HANDLE_ENTRY entry;
        while ((status = PssWalkSnapshot(snapshot, PSS_WALK_HANDLES, marker,
                                        &entry, sizeof(entry))) == ERROR_SUCCESS) {
            /* Borrowed original handle, never close it. GetThreadId safely
             * rejects non-thread handles; no query of object/file contents. */
            DWORD id = GetThreadId(entry.Handle);
            if (id != 0) emit((uintptr_t)entry.Handle, id);
        }
        PssWalkMarkerFree(marker);
    }
    PssFreeSnapshot(GetCurrentProcess(), snapshot);
    return status == ERROR_NO_MORE_ITEMS ? ERROR_SUCCESS : status;
}

/* Numeric object metadata only. No object/file names, VM or stack capture.
 * All snapshot/marker handles are owned and released here; entry handles are
 * borrowed originals and must NEVER be closed by this diagnostic.
 */
static void object_type_label(HANDLE handle, char name[96]) {
    typedef NTSTATUS (NTAPI *QueryObject)(HANDLE, OBJECT_INFORMATION_CLASS, PVOID, ULONG, PULONG);
    HMODULE module = GetModuleHandleW(L"ntdll.dll"); /* borrowed */
    QueryObject query = module ? (QueryObject)GetProcAddress(module, "NtQueryObject") : NULL;
    name[0] = '?'; name[1] = 0;
    if (!query) return;
    union { PUBLIC_OBJECT_TYPE_INFORMATION info; BYTE bytes[2048]; } buffer;
    ULONG returned = 0;
    /* ObjectTypeInformation only: NEVER query ObjectNameInformation, which
     * could expose paths or block on a pipe. No foreign process handles. */
    if (query(handle, ObjectTypeInformation, &buffer, sizeof(buffer), &returned) < 0) return;
    const UNICODE_STRING *type = &buffer.info.TypeName;
    uintptr_t begin = (uintptr_t)buffer.bytes, end = begin + sizeof(buffer.bytes);
    uintptr_t text = (uintptr_t)type->Buffer;
    if (!text || text < begin || text > end || type->Length > end - text || (type->Length & 1)) return;
    size_t length = type->Length / sizeof(WCHAR);
    if (length >= 96) return;
    for (size_t i = 0; i < length; ++i) {
        WCHAR ch = type->Buffer[i];
        name[i] = ch >= 32 && ch <= 126 ? (char)ch : '?';
    }
    name[length] = 0;
}

DWORD localterm_win32_handle_inventory(void (*emit)(uintptr_t, DWORD, DWORD, DWORD, const char *)) {
    HPSS snapshot = NULL;
    PSS_CAPTURE_FLAGS flags = (PSS_CAPTURE_FLAGS)(PSS_CAPTURE_HANDLES |
        PSS_CAPTURE_HANDLE_BASIC_INFORMATION | PSS_CAPTURE_HANDLE_TYPE_SPECIFIC_INFORMATION);
    DWORD status = PssCaptureSnapshot(GetCurrentProcess(), flags, 0, &snapshot);
    if (status != ERROR_SUCCESS) return status;
    HPSSWALK marker = NULL;
    status = PssWalkMarkerCreate(NULL, &marker);
    if (status == ERROR_SUCCESS) {
        PSS_HANDLE_ENTRY entry;
        while ((status = PssWalkSnapshot(snapshot, PSS_WALK_HANDLES, marker,
                                        &entry, sizeof(entry))) == ERROR_SUCCESS) {
            DWORD target = 0;
            if (entry.Flags & PSS_HANDLE_HAVE_TYPE_SPECIFIC_INFORMATION) {
                if (entry.ObjectType == PSS_OBJECT_TYPE_THREAD) target = entry.TypeSpecificInformation.Thread.ThreadId;
                if (entry.ObjectType == PSS_OBJECT_TYPE_PROCESS) target = entry.TypeSpecificInformation.Process.ProcessId;
            }
            DWORD kind = (entry.Flags & PSS_HANDLE_HAVE_TYPE) ? (DWORD)entry.ObjectType : 0;
            DWORD access = (entry.Flags & PSS_HANDLE_HAVE_BASIC_INFORMATION) ? entry.GrantedAccess : 0;
            char label[96];
            object_type_label(entry.Handle, label);
            emit((uintptr_t)entry.Handle, kind, target, access, label);
        }
        PssWalkMarkerFree(marker);
    }
    PssFreeSnapshot(GetCurrentProcess(), snapshot);
    return status == ERROR_NO_MORE_ITEMS ? ERROR_SUCCESS : status;
}
