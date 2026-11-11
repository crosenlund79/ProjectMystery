/* Test shim standing in for py.exe / python.exe under Wine.
 * Forwards to a native Linux interpreter through Wine's __wine_unix_spawnvp, passing on
 * the PYTHON* and MYSTERY_* variables that cmd.exe set. With SHIM_FAKE_VERSION it instead
 * impersonates an old Python: "-V" prints that version, anything else exits 3. */
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <wchar.h>

typedef LONG (WINAPI *spawnvp_t)(char *const argv[], int wait);

static char *utf8(const wchar_t *w) {
    int n = WideCharToMultiByte(CP_UTF8, 0, w, -1, NULL, 0, NULL, NULL);
    char *s = malloc(n);
    WideCharToMultiByte(CP_UTF8, 0, w, -1, s, n, NULL, NULL);
    return s;
}

int main(void) {
    int argc;
    wchar_t **wargv = CommandLineToArgvW(GetCommandLineW(), &argc);
    int first = 1;
#ifdef PY_LAUNCHER
    if (argc > 1 && wcsncmp(wargv[1], L"-3", 2) == 0) first = 2;   /* "py -3 ..." */
#endif
    wchar_t fake[64];
    if (GetEnvironmentVariableW(L"SHIM_FAKE_VERSION", fake, 64)) {
        if (argc > first && wcscmp(wargv[first], L"-V") == 0) { wprintf(L"Python %ls\n", fake); return 0; }
        return 3;
    }
    char *argv[512];
    int k = 0;
    argv[k++] = "/usr/bin/env";
    wchar_t *env = GetEnvironmentStringsW();
    for (wchar_t *e = env; *e; e += wcslen(e) + 1) {
        if ((wcsncmp(e, L"PYTHON", 6) == 0 || wcsncmp(e, L"MYSTERY_", 8) == 0) && k < 400) argv[k++] = utf8(e);
    }
    wchar_t target[1024];
    argv[k++] = GetEnvironmentVariableW(L"SHIM_TARGET", target, 1024) ? utf8(target) : "/usr/bin/python3";
    for (int i = first; i < argc && k < 510; i++) argv[k++] = utf8(wargv[i]);
    argv[k] = NULL;
    spawnvp_t spawn = (spawnvp_t)GetProcAddress(GetModuleHandleW(L"ntdll.dll"), "__wine_unix_spawnvp");
    if (!spawn) { fprintf(stderr, "shim: not running under Wine\n"); return 9009; }
    fflush(stdout);
    return (int)spawn(argv, 1);
}
