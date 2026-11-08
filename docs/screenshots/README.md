# RemoteVoice interface screenshots

Native AppKit / SceneKit renders of the current source, captured on 2026-11-09 in an isolated configuration. These are UI illustrations, not hardware acceptance evidence. No recording, device UUID, account, or personal model path is included. Permission and connection values reflect the renderer context and should not be interpreted as universal readiness.

| File | View |
| --- | --- |
| home-light.png | Chinese, light appearance |
| home-dark.png | Chinese, dark appearance |
| home-english.png | English, light appearance |
| home-dark-english.png | English, dark appearance |
| remote-model.png | SceneKit remote render |
| controls.png | Native settings detail |

The same `RemoteHomeView`, materials and controls used by the application are rendered directly. AppKit captures are composited with `SCNView.snapshot()` because offscreen AppKit caching does not include the SceneKit drawable. No generated product mockup is substituted. External dependencies and model files are not needed to render the interface. The product model was retained from the user-approved previous version.

Regenerate on macOS with Swift 6+: `./scripts/render-doc-screenshots.sh`.
