# Proposal

## Why

Windows 用户目前只能解压便携 ZIP，缺少安装、快捷方式、升级与系统卸载入口。需要复用现有自包含载荷提供可安装版本，并保持当前用户身份与精确操作授权。

## What Changes

- 为 Windows 11 x64、ARM64 增加固定版本 Velopack 当前用户安装器，继续提供便携 ZIP 和独立 CLI。
- 使用独立安装身份 `Limecloud.Shou`，安装根与既有 `%LOCALAPPDATA%/Shou` 数据根分离；安装、升级和卸载不修改现有数据 ACL，不删除用户配置和记录。
- 主程序保持 `asInvoker`，不增加常驻特权服务、全局 ACL 放宽或任何公开变更门禁绕过。
- 安装版更新入口下载对应架构、确切版本的 Setup 覆盖升级；便携版继续下载 ZIP。不增加后台检查、自动安装或自动重启。
- 增加可配置的 Authenticode/时间戳签名及最终字节检查，明确区分未签名预览与有可信签名的产物。
- 扩展发布附件、校验和、安装生命周期生成夹具与双语文档。

## Capabilities

### New Capabilities

- `windows-installation`: Windows 当前用户安装、升级、卸载、权限和安装产物验证。

### Modified Capabilities

无；当前 OpenSpec 尚无持久能力规范。

## Impact

影响 Windows App 入口和依赖锁、桌面更新解析及对话框、Windows 打包/验证脚本、GitHub 发布工作流、共享文案生成与双语安装/发布文档。新增固定版本的 Velopack 应用依赖及 vpk 构建工具。Core 清理策略、用户数据格式、macOS 运行逻辑和 npm CLI 生命周期保持现有合同。
