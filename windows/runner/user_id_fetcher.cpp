#include <windows.h>
#include <tlhelp32.h>
#include <iostream>
#include <vector>
#include <string>

const BYTE* aobscan(const BYTE* pattern, size_t patternLen, const BYTE* buffer, size_t bufferLen)
{
    if (patternLen == 0 || bufferLen < patternLen)
        return nullptr;
    size_t badCharShift[256];
    for (size_t i = 0; i < 256; i++)
        badCharShift[i] = patternLen;
    for (size_t i = 0; i < patternLen - 1; i++)
        badCharShift[pattern[i]] = patternLen - 1 - i;

    size_t i = 0;
    while (i + patternLen <= bufferLen) {
        size_t j = patternLen - 1;
        while (j < patternLen && pattern[j] == buffer[i + j]) {
            if (j == 0)
                return buffer + i;
            j--;
        }
        i += badCharShift[buffer[i + patternLen - 1]];
    }
    return nullptr;
}

uintptr_t ScanProcessMemory(HANDLE hProcess, const BYTE* pattern, size_t patternLen)
{
    SYSTEM_INFO sysInfo;
    GetSystemInfo(&sysInfo);

    uintptr_t addr = (uintptr_t)sysInfo.lpMinimumApplicationAddress;
    uintptr_t maxAddr = (uintptr_t)sysInfo.lpMaximumApplicationAddress;

    MEMORY_BASIC_INFORMATION mbi;
    const SIZE_T bufferSize = 65536;
    std::vector<BYTE> buffer(bufferSize);

    while (addr < maxAddr) {
        if (VirtualQueryEx(hProcess, (LPCVOID)addr, &mbi, sizeof(mbi)) == sizeof(mbi)) {
            if (mbi.State == MEM_COMMIT &&
                (mbi.Protect & PAGE_READWRITE || mbi.Protect & PAGE_READONLY || mbi.Protect & PAGE_EXECUTE_READ || mbi.Protect & PAGE_EXECUTE_READWRITE)) {

                SIZE_T regionSize = mbi.RegionSize;
                uintptr_t regionBase = (uintptr_t)mbi.BaseAddress;

                SIZE_T offset = 0;
                while (offset < regionSize) {
                    SIZE_T toRead = std::min(bufferSize, regionSize - offset);
                    SIZE_T bytesRead = 0;
                    if (ReadProcessMemory(hProcess, (LPCVOID)(regionBase + offset), buffer.data(), toRead, &bytesRead) && bytesRead > 0) {
                        const BYTE* found = aobscan(pattern, patternLen, buffer.data(), bytesRead);
                        if (found) {
                            uintptr_t foundAddr = regionBase + offset + (found - buffer.data());
                            return foundAddr;
                        }
                    }
                    else {
                        break;
                    }
                    offset += toRead;
                }
            }
            addr += mbi.RegionSize;
        }
        else {
            break;
        }
    }
    return 0;
}
// FFI Export function, adapted from user's main() logic
BYTE data[33] = { 0 };
extern "C" __declspec(dllexport) const char* fetch_user_id()
{
   
    HWND hwnd = FindWindowW(NULL, L"体锻打卡");
    DWORD pid = 0;
    GetWindowThreadProcessId(hwnd, &pid);
    HANDLE hProcess = OpenProcess(PROCESS_VM_READ | PROCESS_QUERY_INFORMATION, FALSE, pid);
    BYTE pattern[] = { 0x3F, 0x7B, 0x22, 0x64, 0x61, 0x74, 0x61, 0x22, 0x3A, 0x22 };  // "?{"data":"
    uintptr_t addr = ScanProcessMemory(hProcess, pattern, sizeof(pattern));
    ReadProcessMemory(hProcess, (const void*)(addr + sizeof(pattern)), data, 32, NULL);
    CloseHandle(hProcess);
    return reinterpret_cast<const char*>(data);
}
