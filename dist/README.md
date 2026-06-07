# Installer

The one-click installer **`Bakta-Windows-1.12.0-Setup.exe`** is published on the
[**Releases**](https://github.com/MrMufasii/Bakta-for-Windows/releases) page (it is a
~300 MB self-contained bundle — embedded Python + Bakta + Strawberry Perl + the ported
tool stack — so it is distributed as a release asset rather than committed to the repo).

Rebuild it yourself from a clone with:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\installer\build_bakta_installer.ps1
```

(Requires [Inno Setup 6](https://jrsoftware.org/isdl.php). The script downloads an
embeddable Python, `pip install`s Bakta into it, and compiles the Setup.exe here.)
