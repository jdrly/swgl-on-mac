/* swgl-dpapi.exe: Windows DPAPI for the game's saved password, run inside the app's Wine.
 *
 * The game client reads legends.cfg loginClientEncHashedPassword through CryptUnprotectData.
 * On Windows the official launcher writes it with CryptProtectData; on macOS it cannot (it
 * writes plain base64), so the wine shim converts the password with this tool.
 *
 *   swgl-dpapi.exe protect   stdin: the password (UTF-8)   stdout: the DPAPI blob, base64
 *   swgl-dpapi.exe check     stdin: a base64 DPAPI blob    exit 0 if this prefix can decrypt it
 *
 * Same call as the launcher's windpapi4j: no description, no entropy, UI forbidden.
 */
#include <windows.h>
#include <wincrypt.h>
#include <fcntl.h>
#include <io.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static BYTE *read_stdin(DWORD *len)
{
    size_t cap = 256, n = 0, got;
    BYTE *buf = malloc(cap);
    _setmode(_fileno(stdin), _O_BINARY);
    while (buf && (got = fread(buf + n, 1, cap - n, stdin)) > 0) {
        n += got;
        if (n == cap) {
            BYTE *bigger = realloc(buf, cap *= 2);
            if (!bigger) { free(buf); return NULL; }
            buf = bigger;
        }
    }
    *len = (DWORD)n;
    return buf;
}

static int protect(void)
{
    DWORD len, chars = 0;
    BYTE *text = read_stdin(&len);
    DATA_BLOB in, out;
    char *b64;
    if (!text || !len) return 1;
    in.cbData = len;
    in.pbData = text;
    if (!CryptProtectData(&in, NULL, NULL, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &out)) return 1;
    SecureZeroMemory(text, len);
    if (!CryptBinaryToStringA(out.pbData, out.cbData, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, NULL, &chars))
        return 1;
    b64 = malloc(chars);
    if (!b64 || !CryptBinaryToStringA(out.pbData, out.cbData, CRYPT_STRING_BASE64 | CRYPT_STRING_NOCRLF, b64, &chars))
        return 1;
    _setmode(_fileno(stdout), _O_BINARY);
    fputs(b64, stdout);
    LocalFree(out.pbData);
    return 0;
}

static int check(void)
{
    DWORD len, size = 0;
    BYTE *b64 = read_stdin(&len), *blob;
    DATA_BLOB in, out;
    if (!b64 || !len) return 1;
    if (!CryptStringToBinaryA((char *)b64, len, CRYPT_STRING_BASE64, NULL, &size, NULL, NULL)) return 1;
    blob = malloc(size);
    if (!blob || !CryptStringToBinaryA((char *)b64, len, CRYPT_STRING_BASE64, blob, &size, NULL, NULL)) return 1;
    in.cbData = size;
    in.pbData = blob;
    if (!CryptUnprotectData(&in, NULL, NULL, NULL, NULL, CRYPTPROTECT_UI_FORBIDDEN, &out)) return 1;
    SecureZeroMemory(out.pbData, out.cbData);
    LocalFree(out.pbData);
    return 0;
}

int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "protect")) return protect();
    if (argc == 2 && !strcmp(argv[1], "check")) return check();
    fputs("usage: swgl-dpapi.exe protect|check  (data on stdin)\n", stderr);
    return 2;
}
