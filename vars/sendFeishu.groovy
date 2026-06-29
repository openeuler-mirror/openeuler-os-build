import groovy.json.JsonOutput
import com.cloudbees.groovy.cps.NonCPS

def call(Map args = [:]) {
    def title       = args.title       ?: '构建通知'
    def project     = args.project     ?: ''
    def detail      = args.detail      ?: ''
    def isSuccess   = args.isSuccess != null ? args.isSuccess : true
    def statusEmoji = isSuccess ? '✅' : '❌'
    def statusColor = isSuccess ? 'green' : 'red'
    def noteText    = args.note        ?: 'Jenkins 流水线自动通知'
    def buildUrl    = args.buildUrl    ?: (env.BUILD_URL ?: '')
    def statusText  = args.statusText  ?: ''
    def duration    = args.duration    ?: ''
    def jobLines    = args.jobLines    ?: ''
    def showButton  = args.showButton  ?: false

    def elements = []

    if (statusText || duration) {
        def content = ''
        if (statusText) content += "**流水线状态：**${statusEmoji} ${statusText}\n"
        if (duration)  content += "**耗时：**${duration}"
        elements << [tag: 'div', text: [tag: 'lark_md', content: content]]
    }

    def mainContent = ''
    if (project) mainContent += "**项目：**${project}\n"
    if (detail)  mainContent += "${detail}"
    if (!statusText && !duration) {
        if (mainContent) mainContent += "\n"
        mainContent += "**构建详情：**[点击查看](${buildUrl})"
    }
    if (mainContent) {
        elements << [tag: 'div', text: [tag: 'lark_md', content: mainContent]]
    }

    if (jobLines) {
        elements << [tag: 'hr']
        elements << [tag: 'div', text: [tag: 'lark_md', content: "**各 Job 执行情况：**\n${jobLines}"]]
    }

    if (showButton) {
        elements << [tag: 'hr']
        elements << [tag: 'action', actions: [
            [tag: 'button', text: [tag: 'plain_text', content: '查看构建详情'], url: buildUrl, type: 'default']
        ]]
    }

    elements << [tag: 'note', elements: [
        [tag: 'plain_text', content: noteText]
    ]]

    def card = [
        msg_type: 'interactive',
        card: [
            header: [
                title: [tag: 'plain_text', content: "${statusEmoji} ${title}"],
                template: statusColor
            ],
            elements: elements
        ]
    ]

    def jsonStr = toJson(card)
    def payloadFile = ".feishu_payload_${System.currentTimeMillis()}.json"

    def maxRetries = 3
    def attempt = 0
    def success = false
    try {
        withCredentials([
            string(credentialsId: 'FEISHU_WEBHOOK', variable: 'FEISHU_WEBHOOK')
        ]) {
            writeFile file: payloadFile, text: jsonStr
            while (attempt < maxRetries && !success) {
                attempt++
                try {
                    // 同时获取响应 body 和 HTTP 状态码（最后一行为状态码）
                    def response = sh(
                        script: "curl -s -w '\\n%{http_code}' --connect-timeout 10 --max-time 30 -X POST \"\${FEISHU_WEBHOOK}\" -H \"Content-Type: application/json\" -d @${payloadFile}",
                        returnStdout: true
                    ).trim()
                    def lines = response.readLines()
                    def httpCode = lines.remove(lines.size() - 1).trim()
                    def body = lines.join('\n').trim()

                    if (httpCode.startsWith('2')) {
                        try {
                            def json = readJSON(text: body)
                            if (json?.code == 0) {
                                success = true
                                echo "飞书通知发送成功 (HTTP ${httpCode}, code: ${json.code})"
                            } else {
                                echo "⚠️ 飞书通知业务失败 (HTTP ${httpCode}, code: ${json?.code}, msg: ${json?.msg})，第 ${attempt}/${maxRetries} 次尝试"
                            }
                        } catch (Exception e) {
                            // body 非 JSON 但 HTTP 2xx，视为成功
                            success = true
                            echo "飞书通知发送成功 (HTTP ${httpCode})"
                        }
                    } else {
                        echo "⚠️ 飞书通知响应异常 (HTTP ${httpCode})，第 ${attempt}/${maxRetries} 次尝试"
                    }
                } catch (Exception e) {
                    echo "⚠️ 飞书通知发送失败 (第 ${attempt}/${maxRetries} 次): ${e.message}"
                }
                if (!success && attempt < maxRetries) {
                    sleep 5
                }
            }
            if (!success) {
                echo "⚠️ 飞书通知发送失败：已重试 ${maxRetries} 次仍不成功"
            }
        }
    } catch (Exception e) {
        echo "⚠️ 飞书通知发送失败: ${e.message}"
    } finally {
        sh "rm -f ${payloadFile}"
    }
}

@NonCPS
def toJson(def card) {
    JsonOutput.toJson(card)
}
