# Third-party notices

Lucent is licensed under the GPL-3.0.

## Code included in Lucent

| Project | License | Where |
|---|---|---|
| [YARA](https://github.com/VirusTotal/yara) 4.5.4 by VirusTotal | BSD-3-Clause (see `Packages/LucentKit/Sources/CYara/LICENSE`) | `Packages/LucentKit/Sources/CYara`: libyara, used to read Apple's XProtect rules |

## Data and knowledge reused

| Project | License | What Lucent reuses |
|---|---|---|
| [Mole](https://github.com/tw93/Mole) by tw93 | GPL-3.0 | Cleaning locations and the list of caches that must never be removed (`SAFETY_WHITELIST_PATTERNS`), in `SafetyGuard` and the rule files |
| Apple XProtect | Apple, installed with macOS | Malware signatures, read in place from `/Library/Apple/System/Library/CoreServices/XProtect.bundle`; never copied or redistributed |

## Projects that inspired the design (no code copied)

| Project | License | Inspiration |
|---|---|---|
| [Mac Sai](https://github.com/iliyami/MacSai) | BSD-3-Clause | Module structure, System Junk categories |
| [PureMac](https://github.com/momenbasel/PureMac) | MIT | Cleanup locations, protection checks |
| [KnockKnock](https://github.com/objective-see/KnockKnock) by Objective-See | GPL-3.0 | Inspecting persistence (launch agents and daemons) to reveal malware |
| [Latest](https://github.com/mangerlahn/Latest) | GPL-3.0 | Checking updates through Sparkle feeds and the App Store |
| [Stats](https://github.com/exelban/stats) | MIT | Menu bar system metrics |

Lucent does not use code from Pearcleaner: its Apache-2.0 + Commons Clause license is not compatible with the GPL.

CleanMyMac is a trademark of MacPaw. Lucent is an independent project and uses none of its code, names or artwork.
