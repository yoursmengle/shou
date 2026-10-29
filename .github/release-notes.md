Shou v0.20.0 simplifies everyday navigation, introduces a toolbox entry and gives software updates a dedicated page.

- Focus the main navigation on Cleanup, Applications, Space Analysis and Monitor. Toolbox, History and Settings remain directly accessible; cleanup rules and project cleanup move into Cleanup Options.
- Open AI Workbench or Developer Tools from Toolbox before starting their inventories. Tool navigation shows name, status and an arrow; service switches stay beside the exact instances in details.
- Separate installed applications, software updates and startup items. macOS software updates use Homebrew or mise; Windows uses the verified WinGet source in a persistent page with a fixed review/action area. Checks start only on request, and upgrade execution retains its exact-selection confirmation and navigation protection.
- Simplify the cleanup welcome page with application, space and privacy entries, concise copy and fewer decorative effects. Keep shared English/Chinese text and platform navigation aligned.
- Add self-contained Windows x64/ARM64 current-user Setup installers alongside portable ZIPs. Installed builds download Setup for manual upgrades; configuration and history remain outside the installation root and survive uninstall. The app retains ordinary user privileges and existing operation gates.
- Include the macOS privacy-discovery fix from [PR #1](https://github.com/limecloud/shou/pull/1): inaccessible browser roots no longer hide independently accessible sources. Coverage gaps remain visible, and cleanup still requires exact source validation and confirmation.

macOS supports 14+, Apple Silicon and Intel, with universal DMG/ZIP, standalone CLI, Sparkle-signed updates and checksums. The app uses an ad-hoc signature and is not Apple-notarized. Windows Setup and portable ZIPs remain unsigned, self-contained previews for Windows 11; public cleanup, uninstall and startup mutation gates stay closed. Generated-identity installation, replacement upgrade, ordinary-user window startup and uninstall passed on Windows 11 x64, preserving data and ACLs. ARM64 native installation, clean-system and trusted-signing acceptance remain separate gaps; automatic updating is not implemented. Finish ongoing operations and quit before running an external installer or uninstaller, which may force-stop a running app. Windows developer services/installers, MySQL administration and package upgrades retain their documented acceptance gaps. The new navigation and update page have no new Windows 11 Computer Use acceptance; full accessibility and ARM64 tray interaction remain pending. GitHub publication stages macOS npm tarballs; npm registry publication is separate.

简体中文：Shou v0.20.0 简化日常导航，新增工具箱入口，并将软件更新整理为独立页面。

- 主导航聚焦清理、应用、空间分析和监控；工具箱、操作记录和设置保持直接可达。清理规则与项目清理从“清理选项”进入。
- 从工具箱选择 AI 工作台或开发者工具后才启动对应盘点。工具导航统一展示名称、状态及箭头，服务启停位于右侧确切实例行。
- 应用管理、软件更新和启动项分为独立任务。macOS 软件更新使用 Homebrew／mise 来源；Windows 使用经过核实的 WinGet 来源，页内保留检查结果和固定审阅操作区。仅在用户主动请求后检查，升级继续绑定确切选择、单次确认和执行期间导航保护。
- 简化清理首页，提供应用、空间分析与隐私入口，精简文案和装饰动效，同步中英文文案与两端导航。
- 增加 Windows x64／ARM64 当前用户自包含 Setup，继续提供便携 ZIP。安装版通过下载 Setup 手动升级；配置与历史独立于安装目录，卸载后保留。主程序使用普通用户权限，现有操作门禁保持。
- 纳入 [PR #1](https://github.com/limecloud/shou/pull/1) 的 macOS 隐私发现修复：浏览器目录不可访问时保留其他可访问来源，明确展示覆盖缺口；清理仍须确切来源核验和确认。

macOS 支持 14+、Apple Silicon 与 Intel，提供通用 DMG／ZIP、独立 CLI、Sparkle 签名更新及校验和；应用为 ad-hoc 签名，未经 Apple 公证。Windows Setup 与 ZIP 仍为 Windows 11 未签名自包含预览，公开清理、卸载及启动项变更门禁保持关闭。Windows 11 x64 已通过随机身份安装、覆盖升级、普通用户窗口启动及卸载，数据与 ACL 保留；ARM64 原生安装、干净系统及可信签名仍须分别验收，未实现自动更新。运行外部安装／卸载程序前须完成当前操作并退出，否则可能被强停。Windows 开发服务、安装器、MySQL 管理及软件包升级保留文档所列验收缺口；新导航与软件更新页尚无新的 Windows 11 Computer Use 验收，完整辅助功能和 ARM64 托盘交互仍待完成。GitHub 流水线准备 macOS npm 包，registry 发布单独管理。
