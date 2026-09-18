import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// 一个把受保护的 `layer` 合法暴露出来的 `RepaintBoundary`。
///
/// 为什么需要它：分片栅格化必须拿到 boundary 的 [OffsetLayer] 才能按局部矩形
/// 抓图（`OffsetLayer.toImage(bounds)`）。而 `RenderRepaintBoundary.layer` 是
/// `@protected`，外部无法访问。子类内部访问是合法的，于是在这里暴露一个
/// `publicLayer`，让 [MedicationReportRenderer] 可以安全分片。
class MedicationReportBoundary extends SingleChildRenderObjectWidget {
  const MedicationReportBoundary({super.key, super.child});

  @override
  _ExposedRenderRepaintBoundary createRenderObject(BuildContext context) =>
      _ExposedRenderRepaintBoundary();
}

class _ExposedRenderRepaintBoundary extends RenderRepaintBoundary {
  /// 暴露 `layer`（基类中为 `@protected`，子类内可访问）。
  ///
  /// 静态类型是 `ContainerLayer?`，但 `RenderRepaintBoundary` 的合成层
  /// 运行时必然是 [OffsetLayer]（`updateCompositedLayer` 创建的就是它），
  /// 故在此安全地窄化类型；万一不是则返回 null，走整图兜底。
  OffsetLayer? get publicLayer {
    final l = layer;
    return l is OffsetLayer ? l : null;
  }
}

/// =============================================================================
/// MedicationReportRenderer — 把报告 Widget 栅格化为 PNG 字节
///
/// 为什么分片（决策 D4）：报告是「用药记录 + 价格」的长图，随记录数线性增长。
/// GPU 对单张纹理有最大尺寸（常见 8192 / 16384 px），`toImage` 一旦超限就会
/// **白图或直接失败**。因此这里按「设备像素高度上限」把长图切成多条横向切片，
/// 逐片栅格化，各输出一张 PNG。
///
/// 关键实现：
///   - 用 `OffsetLayer.toImage(bounds)` 抓取**局部矩形** → 这是分片的支点；
///   - `bounds` 以 boundary 自身左上角为原点，故不受祖先滚动/缩放变换影响；
///   - 每片独立编码后立刻 `dispose()`，峰值内存只有「一片」而不是整图。
/// =============================================================================
class MedicationReportRenderer {
  MedicationReportRenderer._();

  /// 单张切片的**最大设备像素高度**（6000 远低于常见纹理上限，留足余量）
  static const int maxSliceDevicePx = 6000;

  /// 分片数量上限（防御性：避免异常输入产生成百上千张图）
  static const int maxSlices = 24;

  /// 将 [boundaryKey] 对应的 [MedicationReportBoundary] 渲染为一张或多张 PNG。
  ///
  /// - 返回**空列表 = 渲染失败**，调用方必须提示用户，不要当成成功；
  /// - 正常情况下：内容不高 → 1 张；内容很高 → 多张（顺序自上而下）。
  ///
  /// [pixelRatio] 越大越清晰，但单片逻辑高度上限随之变小（片数变多）。
  static Future<List<Uint8List>> renderPng(
    GlobalKey boundaryKey, {
    double pixelRatio = 3.0,
  }) async {
    final result = <Uint8List>[];

    final BuildContext? ctx = boundaryKey.currentContext;
    if (ctx == null) {
      debugPrint('📤 [TP-Report] ❌ boundary context 为空（Widget 未挂载？）');
      return result;
    }
    final RenderObject? ro = ctx.findRenderObject();
    if (ro is! _ExposedRenderRepaintBoundary) {
      debugPrint('📤 [TP-Report] ❌ 未找到 MedicationReportBoundary');
      return result;
    }

    final double pr = (pixelRatio.isFinite && pixelRatio > 0) ? pixelRatio : 3.0;
    final Size size = ro.size;
    if (size.width <= 0 || size.height <= 0) {
      debugPrint('📤 [TP-Report] ❌ 尺寸非法: $size');
      return result;
    }

    // 首帧可能尚未产生 layer，等一帧再取
    //
    // ⚠️ 不用 `debugNeedsPaint`：它在 release 下会抛 LateInitializationError。
    OffsetLayer? layer = ro.publicLayer;
    if (layer == null) {
      await Future<void>.delayed(const Duration(milliseconds: 32));
      layer = ro.publicLayer;
    }

    final double sliceLogical = math.max(1.0, maxSliceDevicePx / pr);

    try {
      // ── 兜底：仍拿不到 layer → 退回整图（小报告依然可用）──
      if (layer == null) {
        debugPrint('📤 [TP-Report] ⚠️ layer 为空，退回整图渲染');
        final ui.Image whole = await ro.toImage(pixelRatio: pr);
        final ByteData? data =
            await whole.toByteData(format: ui.ImageByteFormat.png);
        whole.dispose();
        if (data != null) result.add(data.buffer.asUint8List());
        return result;
      }

      // ── 逐片抓取 ──
      double y = 0;
      while (y < size.height - 0.5 && result.length < maxSlices) {
        final double h = math.min(sliceLogical, size.height - y);
        if (h < 1) break;

        final ui.Image slice = await layer.toImage(
          Rect.fromLTWH(0, y, size.width, h),
          pixelRatio: pr,
        );
        final ByteData? data =
            await slice.toByteData(format: ui.ImageByteFormat.png);
        slice.dispose();

        if (data == null) {
          debugPrint('📤 [TP-Report] ❌ 第 ${result.length + 1} 片编码失败');
          break;
        }
        result.add(data.buffer.asUint8List());
        y += h;
      }

      if (y < size.height - 0.5) {
        debugPrint(
            '📤 [TP-Report] ⚠️ 达到分片上限 $maxSlices，剩余内容未导出（源高 ${size.height}）');
      }
      debugPrint('📤 [TP-Report] ✅ 渲染完成: ${result.length} 片, '
          '源尺寸 ${size.width}×${size.height}, pixelRatio=$pr');
      return result;
    } catch (e) {
      debugPrint('📤 [TP-Report] ❌ 渲染异常: $e');
      return result;
    }
  }
}
