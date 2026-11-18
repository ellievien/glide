# UNCOMMENT THESE LINES TO BUILD FROM LATEST COMMIT
# git reset --hard origin/main
# git pull

cd app

fvm flutter clean
fvm flutter pub get
fvm flutter build windows

..\support\scripts\copy_windows_crt.ps1 -Arch x64 -Destination build\windows\x64\runner\Release
Compress-Archive -Path build/windows/x64/runner/Release/* -DestinationPath Glide-XXX-windows-x86-64.zip

cd ..

Write-Output 'Generated Windows zip!'