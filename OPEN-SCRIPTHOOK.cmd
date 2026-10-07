@echo off
setlocal
title ScriptHookRDR2 - official download page
echo This opens Alexander Blade's official Script Hook RDR2 page.
echo Click Download, NOT Download SDK.
echo The runtime ZIP includes BOTH ScriptHookRDR2.dll and the ASI loader dinput8.dll.
echo Extract those two DLLs next to RDR2.exe. Do not overwrite existing loaders blindly.
echo NativeTrainer.asi is not required for Assassin Traversal.
echo This helper does not download, execute or install any DLL.
start "" "https://www.dev-c.com/rdr2/scripthookrdr2/"
echo.
echo Full Russian instructions:
echo https://github.com/iskandario/rdr2-lego-windows-check/blob/main/START-HERE-RU.md
pause
