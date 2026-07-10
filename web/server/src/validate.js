// ── 参数校验 ──

// app 名: 字母数字连字符下划线
const APP_NAME_RE = /^[a-zA-Z0-9][-a-zA-Z0-9_]*$/

/**
 * 校验 app 名列表
 * @param {*} apps
 * @returns {string|null} 错误信息或 null
 */
export function validateApps(apps) {
  if (!apps || !Array.isArray(apps) || apps.length === 0) {
    return 'apps 不能为空'
  }
  for (const app of apps) {
    if (typeof app !== 'string' || !APP_NAME_RE.test(app)) {
      return `非法应用名: ${app}`
    }
  }
  return null
}

/**
 * 校验布尔值（可选）
 * @param {*} val
 * @returns {string|null}
 */
export function validateBoolean(val) {
  if (val === undefined || val === null) return null
  if (typeof val !== 'boolean') return '必须为布尔值'
  return null
}

/**
 * 校验非负整数（可选）
 * @param {*} val
 * @returns {string|null}
 */
export function validateNonNegativeInt(val) {
  if (val === undefined || val === null) return null
  if (typeof val !== 'number' || !Number.isInteger(val) || val < 0) {
    return '必须为非负整数'
  }
  return null
}

/**
 * 校验备份文件名（禁止路径遍历）
 * @param {string} archive
 * @returns {string|null}
 */
export function validateArchive(archive) {
  if (!archive || typeof archive !== 'string') {
    return 'archive 不能为空'
  }
  if (archive.startsWith('/')) {
    return 'archive 不允许绝对路径'
  }
  if (archive.includes('..')) {
    return 'archive 不允许路径遍历 (..)'
  }
  return null
}
