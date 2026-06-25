/**
 * CCB 构建状态码常量定义
 *
 * 项目状态码:
 *   201 - 构建成功
 *   202 - 构建失败
 *   203 - 构建超时
 *   205 - 构建异常
 *
 * 软件包状态码:
 *   103 - 软件包构建成功
 */
def call() {
    return [
        // 项目状态码
        projectStatusStop:    [201, 202, 203, 205],
        projectStatusNotice:  [203, 205],
        projectStatusSuccess: 201,
        projectStatusFail:    202,
        // 软件包状态码
        packageStatusSuccess: 103
    ]
}
