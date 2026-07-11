<script setup>
/**
 * AppCardGrid — 统一的可选择应用卡片网格
 *
 * 所有"选 app"场景（备份/还原/部署）共用此组件，
 * 选中态表现为彩色边框 + 右上角勾选图标。
 *
 * Props:
 *   apps           - 应用列表 [{ name, description?, dirs? }]
 *   selected       - v-model: 已选 app 名称数组
 *   selectedDirs   - v-model: { appName: [dirPath, ...] }（showDirs 时生效）
 *   showDirs       - 是否展开目录子选择（仅备份页）
 *   showDescription- 是否显示描述文字
 *   emptyText      - 空态提示文字
 */

import { computed } from 'vue'
import {
  NCard, NGrid, NGi, NText, NTag, NCheckbox, NSpace, NIcon, NEmpty,
} from 'naive-ui'
import { CheckmarkCircle } from '@vicons/ionicons5'

const props = defineProps({
  apps:             { type: Array,   default: () => [] },
  selected:         { type: Array,   default: () => [] },
  selectedDirs:     { type: Object,  default: () => ({}) },
  showDirs:         { type: Boolean, default: false },
  showDescription:  { type: Boolean, default: true },
  emptyText:        { type: String,  default: '暂无应用' },
})

const emit = defineEmits(['update:selected', 'update:selectedDirs'])

// ── 选中集合（方便 O(1) 查找） ──
const selectedSet = computed(() => new Set(props.selected))

// ── 卡片点击：切换选中 ──
function toggle(name) {
  const next = selectedSet.value.has(name)
    ? props.selected.filter(a => a !== name)
    : [...props.selected, name]
  emit('update:selected', next)
}

// ── 目录子选择 ──
function isDirSelected(appName, dirPath) {
  return (props.selectedDirs[appName] || []).includes(dirPath)
}
function toggleDir(appName, dirPath) {
  const current = props.selectedDirs[appName] || []
  const next = current.includes(dirPath)
    ? current.filter(d => d !== dirPath)
    : [...current, dirPath]
  emit('update:selectedDirs', { ...props.selectedDirs, [appName]: next })
}
</script>

<template>
  <div>
    <n-empty v-if="apps.length === 0" :description="emptyText" style="padding: 40px 0" />

    <n-grid v-else :cols="3" :x-gap="12" :y-gap="12" responsive="screen" style="grid-auto-rows: 1fr">
      <n-gi v-for="app in apps" :key="app.name" style="display: flex; flex-direction: column">
        <n-card
          :class="['app-card', { 'app-card--selected': selectedSet.has(app.name) }]"
          size="small"
          hoverable
          @click="toggle(app.name)"
        >
          <!-- 右上角选中标记 -->
          <template v-if="selectedSet.has(app.name)" #header-extra>
            <n-icon size="20" color="#18a058" :component="CheckmarkCircle" />
          </template>

          <!-- 标题 -->
          <template #header>
            <n-text strong>{{ app.name }}</n-text>
          </template>

          <!-- 描述 -->
          <n-text v-if="showDescription && app.description" depth="3" style="font-size: 13px">
            {{ app.description }}
          </n-text>

          <!-- 目录子选择（仅备份页） -->
          <template v-if="showDirs && selectedSet.has(app.name) && app.dirs && app.dirs.length > 0">
            <n-space vertical size="small" style="margin-top: 12px; padding-top: 12px; border-top: 1px solid var(--n-border-color, #eee)" @click.stop>
              <n-text depth="3" style="font-size: 12px">备份目录</n-text>
              <n-checkbox
                v-for="dir in app.dirs"
                :key="dir.path"
                :checked="isDirSelected(app.name, dir.path)"
                @update:checked="toggleDir(app.name, dir.path)"
                size="small"
              >
                <n-text depth="2" style="font-size: 12px">{{ dir.path }}</n-text>
                <n-tag v-if="dir.recommended" size="tiny" type="success" style="margin-left: 4px">推荐</n-tag>
                <n-tag v-if="!dir.exists" size="tiny" type="warning" style="margin-left: 4px">不存在</n-tag>
              </n-checkbox>
            </n-space>
          </template>
        </n-card>
      </n-gi>
    </n-grid>
  </div>
</template>

<style scoped>
.app-card {
  cursor: pointer;
  transition: border-color 0.2s, box-shadow 0.2s;
  border: 2px solid transparent;
  height: 100%;
}
.app-card:hover {
  border-color: var(--n-border-hover-color, #ccc);
}
.app-card--selected {
  border-color: #18a058 !important;
  box-shadow: 0 0 0 1px rgba(24, 160, 88, 0.15);
  background-color: rgba(24, 160, 88, 0.04);
}
</style>
