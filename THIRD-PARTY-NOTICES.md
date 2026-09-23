# Third-party notices

These licences cover only the third-party material identified below. They do
not license Frisket itself. The repository remains private with no project
licence, per decision 43.

## GRDB.swift — MIT

Author: Gwendal Roué and contributors.
Upstream: https://github.com/groue/GRDB.swift

GRDB is an approved future dependency; it is added when first linked. This
advance notice does not mean GRDB is currently linked or vendored. At first
linking, record the pinned version and compare this notice with that version's
LICENSE, retaining its complete copyright and permission notice. The licence
text below was prepared offline; no upstream version was fetched for ticket 01.

```text
The MIT License (MIT)

Copyright (c) 2015 Gwendal Roué

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Matt Pocock skills — MIT

The copied skills in `.cursor/skills/matt-pocock/` come from the
`mattpocock-skills` package, version **1.2.3**. The original
[licence](.cursor/skills/matt-pocock/LICENSE) and
[provenance manifest](.cursor/skills/matt-pocock/provenance.json) are retained
with the copy. The manifest records its local package source and SHA-256 hashes
for the copied files. These are development instructions, not an app dependency.

```text
MIT License

Copyright (c) 2026 Matt Pocock

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

## Snapzy stitcher — BSD-3-Clause (product component)

Copyright (c) 2026, Trong Duong Duc.
Upstream: https://github.com/duongductrong/Snapzy
Source revision: `837fc73d9b55dfde203e9d14aeb8c8fae4f0add7`.

Decision 48 adopts the adapted stitcher in `Sources/FrisketCore/Stitcher/`.
Ticket 34 includes it in the FrisketCore product and moves the ported image
factory and regression tests into `Tests/FrisketCoreTests/Stitcher/`. The
isolated trial package has been retired. File provenance, original and adapted
SHA-256 hashes, and local changes are in
[docs/ported-files.json](docs/ported-files.json). The complete upstream licence
is also retained at [docs/licenses/Snapzy-LICENSE](docs/licenses/Snapzy-LICENSE).

```text
BSD 3-Clause License

Copyright (c) 2026, Trong Duong Duc

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

3. Neither the name of the copyright holder nor the names of its
   contributors may be used to endorse or promote products derived from
   this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
```
