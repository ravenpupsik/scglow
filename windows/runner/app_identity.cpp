#include "app_identity.h"

#include <windows.h>
#include <knownfolders.h>
#include <propkey.h>
#include <propvarutil.h>
#include <shlobj.h>
#include <shobjidl.h>

#include <string>

namespace {

std::wstring ExePath() {
  wchar_t buf[MAX_PATH * 2];
  DWORD n = ::GetModuleFileNameW(nullptr, buf, ARRAYSIZE(buf));
  return std::wstring(buf, n);
}

std::wstring DirOf(const std::wstring& path) {
  auto pos = path.find_last_of(L"\\/");
  return pos == std::wstring::npos ? L"." : path.substr(0, pos);
}

void RegisterAumid(const std::wstring& exe) {
  std::wstring key = L"Software\\Classes\\AppUserModelId\\";
  key += kAppUserModelId;
  HKEY hkey = nullptr;
  if (::RegCreateKeyExW(HKEY_CURRENT_USER, key.c_str(), 0, nullptr, 0,
                        KEY_SET_VALUE, nullptr, &hkey, nullptr) != ERROR_SUCCESS) {
    return;
  }
  auto set = [hkey](const wchar_t* name, const std::wstring& value) {
    ::RegSetValueExW(hkey, name, 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(value.c_str()),
                     static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
  };
  set(L"DisplayName", kAppDisplayName);
  std::wstring icon = DirOf(exe) + L"\\app_icon.ico";
  if (::GetFileAttributesW(icon.c_str()) != INVALID_FILE_ATTRIBUTES) {
    set(L"IconUri", icon);
  }
  ::RegCloseKey(hkey);
}

bool ShortcutIsCurrent(IShellLinkW* link, IPersistFile* file,
                       const std::wstring& lnk, const std::wstring& exe) {
  if (FAILED(file->Load(lnk.c_str(), STGM_READ))) return false;
  wchar_t target[MAX_PATH * 2] = {0};
  if (FAILED(link->GetPath(target, ARRAYSIZE(target), nullptr, 0))) {
    return false;
  }
  if (_wcsicmp(target, exe.c_str()) != 0) return false;
  IPropertyStore* store = nullptr;
  if (FAILED(link->QueryInterface(IID_PPV_ARGS(&store)))) return false;
  PROPVARIANT pv;
  PropVariantInit(&pv);
  bool same = SUCCEEDED(store->GetValue(PKEY_AppUserModel_ID, &pv)) &&
              pv.vt == VT_LPWSTR && wcscmp(pv.pwszVal, kAppUserModelId) == 0;
  PropVariantClear(&pv);
  store->Release();
  return same;
}

bool HasInstallMarker(const std::wstring& exe) {
  const std::wstring marker = DirOf(exe) + L"\\scglow.installed";
  return ::GetFileAttributesW(marker.c_str()) != INVALID_FILE_ATTRIBUTES;
}

// True when the loaded shortcut already points at an installed copy, which a
// portable copy must not take over.
bool PointsToInstalledCopy(IShellLinkW* link) {
  wchar_t target[MAX_PATH * 2] = {0};
  if (FAILED(link->GetPath(target, ARRAYSIZE(target), nullptr, 0)) ||
      target[0] == L'\0') {
    return false;
  }
  return ::GetFileAttributesW(target) != INVALID_FILE_ATTRIBUTES &&
         HasInstallMarker(target);
}

void EnsureStartMenuShortcut(const std::wstring& exe) {
  // The installer owns the shortcuts of an installed copy.
  if (HasInstallMarker(exe)) return;
  PWSTR programs = nullptr;
  if (FAILED(::SHGetKnownFolderPath(FOLDERID_Programs, 0, nullptr,
                                    &programs))) {
    return;
  }
  std::wstring lnk = std::wstring(programs) + L"\\" + kAppDisplayName + L".lnk";
  ::CoTaskMemFree(programs);

  IShellLinkW* link = nullptr;
  if (FAILED(::CoCreateInstance(CLSID_ShellLink, nullptr,
                                CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&link)))) {
    return;
  }
  IPersistFile* file = nullptr;
  if (SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&file)))) {
    if (!ShortcutIsCurrent(link, file, lnk, exe) &&
        !PointsToInstalledCopy(link)) {
      link->SetPath(exe.c_str());
      link->SetWorkingDirectory(DirOf(exe).c_str());
      link->SetIconLocation(exe.c_str(), 0);
      link->SetDescription(kAppDisplayName);
      IPropertyStore* store = nullptr;
      if (SUCCEEDED(link->QueryInterface(IID_PPV_ARGS(&store)))) {
        PROPVARIANT pv;
        if (SUCCEEDED(InitPropVariantFromString(kAppUserModelId, &pv))) {
          store->SetValue(PKEY_AppUserModel_ID, pv);
          store->Commit();
          PropVariantClear(&pv);
        }
        store->Release();
      }
      file->Save(lnk.c_str(), TRUE);
    }
    file->Release();
  }
  link->Release();
}

}

void InitAppIdentity() {
  ::SetCurrentProcessExplicitAppUserModelID(kAppUserModelId);
  const std::wstring exe = ExePath();
  RegisterAumid(exe);
  EnsureStartMenuShortcut(exe);
}
