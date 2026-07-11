<script setup>
defineProps({
  count: { type: Number, default: 6 },
})
</script>

<template>
  <n-grid :cols="3" :x-gap="12" :y-gap="12" responsive="screen">
    <n-gi v-for="i in count" :key="i">
      <n-card size="small">
        <n-skeleton text style="width: 55%" />
        <n-skeleton text style="width: 35%; margin-top: 6px" />
        <n-skeleton text :repeat="2" style="margin-top: 10px" />
      </n-card>
    </n-gi>
  </n-grid>
</template>
