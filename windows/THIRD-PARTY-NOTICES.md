# Third-party software

## scrcpy

Wi-Fi phone audio uses **scrcpy** by Genymobile (Romain Vimont and contributors): <https://github.com/Genymobile/scrcpy>

scrcpy is not included in this patch. The first time you choose Wi-Fi audio, the patch downloads the official scrcpy release (v5.0.1, `scrcpy-win64-v5.0.1.zip`) from scrcpy's GitHub releases. It checks the download against its published SHA-256 before using it, and keeps it in `%LOCALAPPDATA%\vivo-office-kit-english-watcher\scrcpy`. That folder includes scrcpy's own `LICENSE.txt`.

scrcpy is licensed under the Apache License, Version 2.0:

    Copyright (C) 2018 Genymobile
    Copyright (C) 2018-2026 Romain Vimont

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

        http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

The scrcpy download also contains Android's `adb` and other components under their own licenses, listed in scrcpy's release.
