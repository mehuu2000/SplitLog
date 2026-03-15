# Suggested commands
- List project schemes: `xcodebuild -list -project SplitLog.xcodeproj`
- Build app target: `xcodebuild -project SplitLog.xcodeproj -scheme SplitLog -destination 'platform=macOS' build`
- Run tests: `xcodebuild -project SplitLog.xcodeproj -scheme SplitLog -destination 'platform=macOS' test`
- Open project in Xcode: `open SplitLog.xcodeproj`
- Search files/text quickly: `rg --files`, `rg 'pattern' SplitLog`
- Inspect README: `sed -n '1,240p' README.md`
- Inspect memo: `sed -n '1,260p' SplitLog/memo.md`
- Note: no dedicated repo-local lint/format command was found.