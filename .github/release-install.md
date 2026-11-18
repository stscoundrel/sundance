## Installing

The builds aren't signed by a paid certificate, so Windows and macOS ask once before the
first start. After that the game opens like any other.

**Windows.** Unzip `sundance-…-windows.zip` and run `Sundance.exe`. If a blue "Windows
protected your PC" box comes up, click **More info**, then **Run anyway**.

**macOS** (Intel or Apple Silicon). Unzip `sundance-…-macos.zip` and move `Sundance.app`
to Applications (or anywhere you like). Double-clicking it the first time only says it
can't be opened. Then either:

- *macOS 14 Sonoma and older:* right-click (or Ctrl-click) `Sundance.app`, choose **Open**,
  and **Open** again in the box that comes up.
- *macOS 15 Sequoia and newer:* try to open it once, then go to **System Settings >
  Privacy & Security**, scroll down to the line about Sundance, click **Open Anyway** and
  give your password.
- *Or, on any version,* open Terminal and run (with the app's real path):
  `xattr -dr com.apple.quarantine /Applications/Sundance.app`

**Linux** (x86_64). Unpack and run it:
`tar -xzf sundance-…-linux-x86_64.tar.gz && ./Sundance.x86_64`.
If your file manager won't start it, `chmod +x Sundance.x86_64` first.

`SHA256SUMS` lists each download's checksum, to check one with `sha256sum -c SHA256SUMS`
(on macOS, `shasum -a 256 -c SHA256SUMS`).
