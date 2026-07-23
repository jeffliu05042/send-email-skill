# send-email-skill

[English](README.md) | [简体中文](README.zh-CN.md)

一个通过 macOS `/usr/bin/mail` 发送纯文本邮件、安全编码非 ASCII 主题，并从 Postfix 日志核验收件 SMTP 服务器响应的 Agent Skill。

## 功能特点

- 复用本机已经配置好的邮件传输服务，Skill 本身不保存额外的 SMTP 凭证。
- 发送前校验单个收件人、邮件主题和非空正文。
- 使用 RFC 2047 编码非 ASCII 主题，使不支持 `SMTPUTF8` 的服务器也能接收。
- 只有在用户明确授权后才发送，并且每次请求只发送一次。
- 支持从标准输入或纯文本文件读取正文。
- 支持 `--dry-run`，无需实际发信即可完成参数验证。
- 返回确定性的本机接收、远端 SMTP 接受或拒绝以及队列状态标记。

## 环境要求

- macOS，并提供 `/usr/bin/mail`、`/usr/bin/mailq` 和 `/usr/bin/log`
- 使用 `/usr/bin/python3` 标准库完成 RFC 2047 主题编码
- 已正确配置、能够向外部投递邮件的本机 Postfix
- Codex 等兼容 Agent Skills 的客户端

## 安装

使用 Skills CLI 安装：

```bash
npx skills add jeffliu05042/send-email-skill@send-email -g -y
```

也可以为 Codex 手动安装：

```bash
git clone https://github.com/jeffliu05042/send-email-skill.git
mkdir -p ~/.codex/skills
cp -R send-email-skill/skills/send-email ~/.codex/skills/
```

如果客户端没有立即发现该 Skill，请重新启动客户端或新建一个任务。

## 通过 Agent 使用

明确调用 Skill，并提供收件人和发送目的：

```text
使用 $send-email 把发布报告发送到 person@example.com。
```

Agent 应先复核收件人、主题和正文，并且只在用户授权发送后运行随附脚本。脚本只有在 macOS Postfix 日志显示 `status=sent` 后才报告成功。

## 直接使用脚本

通过标准输入传入正文：

```bash
printf '%s\n' '版本发布已经完成。' | \
  skills/send-email/scripts/send_email.sh \
  --to 'person@example.com' \
  --subject '版本发布完成'
```

或者从文件读取正文：

```bash
skills/send-email/scripts/send_email.sh \
  --to 'person@example.com' \
  --subject '版本发布报告' \
  --body-file '/absolute/path/report.txt'
```

只验证、不发送：

```bash
printf '%s\n' '测试正文' | \
  skills/send-email/scripts/send_email.sh \
  --to 'person@example.com' \
  --subject 'Dry run' \
  --dry-run
```

## 结果约定

| 标记 | 含义 |
| --- | --- |
| `DRY_RUN_OK` | 参数验证通过，没有发送邮件。 |
| `SUBJECT_HEADER_READY` | 主题为 ASCII，或已经完成 RFC 2047 编码。 |
| `LOCAL_MAIL_ACCEPTED` | `/usr/bin/mail` 已在本机接收邮件。 |
| `REMOTE_SMTP_ACCEPTED` | 收件 SMTP 服务器已经接受邮件。 |
| `REMOTE_SMTP_REJECTED` | 收件 SMTP 服务器拒绝了邮件。 |
| `REMOTE_DELIVERY_DEFERRED` | Postfix 延迟投递，将在稍后重试。 |
| `REMOTE_DELIVERY_UNCONFIRMED` | 在验证窗口内没有出现最终的远端状态。 |
| `QUEUE_EMPTY` | 本机 Postfix 队列中没有待投递邮件。 |
| `LOCAL_MAIL_REJECTED` | 本机邮件命令拒绝了该邮件。 |
| `QUEUE_STATUS_UNAVAILABLE_AFTER_DELIVERY` | 已确认远端接受，但按需运行的 Postfix 已停止，无法查询全局队列。 |

成功发送需要脚本以状态码 `0` 退出，并输出 `REMOTE_SMTP_ACCEPTED`。这可以确认收件 SMTP 服务器已经接受邮件，但不能证明收件人已经阅读。

## 安全与限制

- 不要在正文中包含密码、API Key、私钥或无关的本机数据。
- 如果上一次结果不确定或失败，应先排查再重试，避免重复发送。
- 当前仅支持一个收件人和纯文本正文。
- HTML、抄送、密送和附件不在当前支持范围内。
- 最终送达和收件箱归类仍取决于本机 Postfix 中继、DNS、发件人配置以及收件侧过滤。

## 项目结构

```text
skills/send-email/
├── SKILL.md
├── agents/openai.yaml
└── scripts/send_email.sh
tests/
├── fixtures/
└── test_send_email.sh
```

## 许可证

[MIT](LICENSE)
