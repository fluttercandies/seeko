<p align="center">
  <img src="assets/brand/seeko-mark-light.svg" alt="Seeko 标志" width="104" height="104">
</p>

<h1 align="center">Seeko</h1>

<p align="center">
  面向 Flutter 原生滚动组件的高性能目标定位与同步库。
</p>

<p align="center">
  <a href="README.md">English</a> · <a href="README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/fluttercandies/seeko/actions/workflows/quality.yml"><img src="https://github.com/fluttercandies/seeko/actions/workflows/quality.yml/badge.svg" alt="质量检查"></a>
  <a href="https://github.com/fluttercandies/seeko/actions/workflows/platforms.yml"><img src="https://github.com/fluttercandies/seeko/actions/workflows/platforms.yml/badge.svg" alt="平台编译检查"></a>
  <a href="https://pub.dev/packages/seeko"><img src="https://img.shields.io/pub/v/seeko.svg" alt="pub package"></a>
  <a href="https://pub.dev/packages/seeko/score"><img src="https://img.shields.io/pub/points/seeko" alt="pub points"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT license"></a>
</p>

Seeko 在 Flutter 的 `ListView`、`GridView`、`CustomScrollView`、`PageView`
和 `NestedScrollView` 之上提供目标定位、自然可取消动画、状态观察和多视图
同步，同时保留 Flutter 对渲染、physics、语义和生命周期的控制。不需要学习
另一套平行的高层组件体系。

## 安装

```bash
flutter pub add seeko
```

本 package 支持 Flutter `>=3.27.0` 和 Dart `>=3.6.0`。

## 快速开始

在 Flutter 接受 `ScrollController` 的地方直接使用 `SeekoController`：

```dart
import 'package:flutter/material.dart';
import 'package:seeko/seeko.dart';

class MessagesPage extends StatefulWidget {
  const MessagesPage({super.key});

  @override
  State<MessagesPage> createState() => _MessagesPageState();
}

class _MessagesPageState extends State<MessagesPage> {
  final SeekoController _controller = SeekoController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: _controller,
      itemCount: 100,
      itemBuilder: (context, index) => ListTile(
        title: Text('Message $index'),
      ),
    );
  }

  Future<void> showTheMiddle() async {
    await _controller.animateToTarget(
      ScrollTarget.progress(0.5),
      placement: const ScrollPlacement.nearest(),
    );
  }
}
```

只需要像素滚动时，继承自 Flutter 的 API 仍然可用：

```dart
_controller.jumpTo(240);
await _controller.animateTo(
  640,
  duration: const Duration(milliseconds: 320),
  curve: Curves.easeOutCubic,
);
```

## 目标定位

`ScrollTarget` 让滚动目的地明确。根据页面需要的保证选择最小接入方式：

| 需求 | 使用方式 | 保证 |
| --- | --- | --- |
| 像素或内容进度 | `ScrollTarget.offset`、`.progress`、`.edge` | 适用于所有已 attach 的原生滚动组件 |
| 已挂载 child | `SeekoTag` 加 `.key`、`.index` 或 `.mounted` | 精确 reveal，支持 placement 和遮挡处理 |
| 大型或可变高度列表中的未挂载 item | `SeekoIndexedSliver` | 基于布局解析 index/key，不构建中间所有 item |

只为确实需要语义定位的 child 添加 tag：

```dart
SeekoTag(
  controller: _controller,
  targetKey: 'message-$index',
  index: index,
  child: Text('Message $index'),
);

final result = await _controller.animateToTarget(
  ScrollTarget.key('message-42'),
  placement: const ScrollPlacement.center(),
);
```

每个 target 命令都会返回类型化的 `ScrollResult`，说明目标是精确完成、被边界
限制、被用户打断、尚未加载还是当前接入方式不支持。非法参数抛出
`ArgumentError` 或 `RangeError`；预期的运行时结果不会被静默吞进无类型的
`Future<void>`。

## 动画与放置

需要立即定位使用 `jumpToTarget`，需要动画使用 `animateToTarget`：

```dart
await _controller.animateToTarget(
  ScrollTarget.edge(ScrollEdge.trailing),
  motion: const ScrollMotion.adaptive(),
  placement: const ScrollPlacement.end(),
);
```

motion 支持 adaptive、instant、显式 duration、velocity 和 spring。placement
支持 start、center、end、nearest、visible，以及精确的 target/viewport anchor。
可以通过 obstruction resolver 排除 pinned header、键盘 inset 或悬浮控件。用户
拖动、滚轮、键盘、滚动条和无障碍操作都可以接管正在执行的命令。

## 同步滚动组件

每个视图保留自己的 controller，由同步组映射它们的逻辑位置：

```dart
final left = SeekoController();
final right = SeekoController();
final group = ScrollSyncGroup.progress();

group.add(left, id: 'left');
group.add(right, id: 'right');

ListView(controller: left, children: leftChildren);
ListView(controller: right, children: rightChildren);
```

内置 mapping 支持 pixels、transaction delta、normalized progress、viewport
fraction 和 semantic anchor。member 可以运行时加入、离开、暂时静音或切换为
offstage。一个同步组同一时间只有一个 leader transaction，增加视图时不会积累
回授循环。

## 常见场景

这些基础能力覆盖通常需要自行编排的滚动场景：

- **分类导航：** 为内容列表的分组标题添加 tag，再用
  `SeekoSectionCoordinator` 连接分类栏。点击分类解析目标，内容滚动时反向更新
  当前分类。
- **顶部横向标签：** 为标签栏使用横向 controller，并用 section coordinator
  连接纵向内容列表，选中状态和内容位置保持双向联动。
- **表单与焦点：** `ensureFocusVisible` 和 `ensureFirstFormErrorVisible`
  在键盘或 pinned header 存在时仍能完整展示字段。
- **嵌套 header：** `SeekoNestedScrollBinding` 协调外层
  `NestedScrollView` 与当前 inner position。
- **Grid 与表格：** `SeekoIndexedGridSliver`、`SeekoTwoDimensionalController`、
  `SeekoTableLayout` 和 `SeekoTreeTableController` 提供 cell/key 定位、冻结窗格、
  展开锚定和键盘导航，同时不替换 Flutter 原生组合方式。
- **页面与开放数据：** `SeekoPageControllerAdapter` 和
  `SeekoOpenScrollAdapter` 为页面、carousel 和双向时间轴保留取消、恢复、加载边界
  与稳定身份。

## 观察状态

只在页面需要时订阅。状态每帧最多合并为一个结构不同的 snapshot：

```dart
ValueListenableBuilder<ScrollSnapshot>(
  valueListenable: _controller.state,
  builder: (context, snapshot, child) {
    return Text(
      '${snapshot.phase.name} · ${(snapshot.progress ?? 0) * 100}%',
    );
  },
);
```

`ScrollSnapshot` 提供逻辑像素、extent、progress、phase、velocity、可见 tagged
target、当前 anchor、活动命令和同步来源。高频 raw event 需要显式 opt-in。

## 性能与边界

Seeko 不会让可选的索引、observer 和同步状态进入普通 controller 的路径。远距离
定位使用稀疏 extent 元数据，不会把每个中间 item 逐个滚过。同步开销与 active
member 数量线性相关，使用共享 transaction，而不是为每个视图创建动画 controller。

任何库都不能替应用代码承诺固定帧率：昂贵的 item build、图片解码、shader 和平台
合成仍由应用负责。对于 extent 未知且尚未构建的 child，普通 `ScrollController`
无法推导精确 offset；需要该保证时使用 indexed primitive，或提供明确的 extent/key
协议给对应 driver。

## 迁移

- 从 `scroll_to_index` 迁移：用 `SeekoController` 替换 `AutoScrollController`，
  用 `SeekoTag` 替换 `AutoScrollTag`，并读取类型化 `ScrollResult`。
- 从 `linked_scroll_controller` 迁移：每个视图创建一个 `SeekoController`，按内容
  关系选择合适的 mapping。
- 从 `scrollable_positioned_list` 迁移：需要精确定位未挂载 index/key 时保留原生
  `CustomScrollView` 并使用 `SeekoIndexedSliver`；`SeekoTag` 是最小侵入的已挂载
  目标路径。

## Example 与参考资料

[`example`](example/README.md) 应用提供可运行的目标定位、分类栏、顶部横向标签、遮挡表单、
Grid、嵌套滚动、页面、开放数据、二维 cell、表格和多视图同步场景。

```bash
cd example
flutter run -d macos
```

更多项目细节请阅读[迁移指南](MIGRATION.md)、[变更记录](CHANGELOG.md)、
[贡献指南](CONTRIBUTING.md)、[安全策略](SECURITY.md)、[社区行为准则](CODE_OF_CONDUCT.md)
和[品牌规范](assets/brand/BRAND.md)。

## 许可证

Seeko 使用 [MIT License](LICENSE)。
