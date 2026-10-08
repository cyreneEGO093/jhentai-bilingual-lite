// Modified for Bilingual Lite (2026-10-07); see NOTICE. Original JHenTai portions: Apache-2.0.
import 'package:animate_do/animate_do.dart';
import 'package:dio/dio.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:get/get.dart';
import 'package:jhentai/src/config/ui_config.dart';
import 'package:jhentai/src/extension/dio_exception_extension.dart';
import 'package:jhentai/src/extension/widget_extension.dart';
import 'package:jhentai/src/model/gallery_stats.dart';
import 'package:jhentai/src/network/eh_request.dart';
import 'package:jhentai/src/utils/eh_spider_parser.dart';
import 'package:jhentai/src/service/log.dart';
import 'package:jhentai/src/utils/snack_util.dart';
import 'package:jhentai/src/widget/loading_state_indicator.dart';
import 'native_visit_chart.dart';

import '../exception/eh_site_exception.dart';

enum GraphType { allTime, year, month, day }

class EHGalleryStatDialog extends StatefulWidget {
  final int gid;
  final String token;

  const EHGalleryStatDialog({Key? key, required this.gid, required this.token}) : super(key: key);

  @override
  State<EHGalleryStatDialog> createState() => _EHGalleryStatDialogState();
}

class _EHGalleryStatDialogState extends State<EHGalleryStatDialog> {
  late GalleryStats galleryStats;
  LoadingState loadingState = LoadingState.idle;

  GraphType graphType = GraphType.allTime;

  @override
  void initState() {
    _getGalleryStats();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SimpleDialog(
      title: Center(child: Text('VisitorStatistics'.tr)),
      children: [
        LoadingStateIndicator(
          loadingState: loadingState,
          successWidgetBuilder: () => Column(
            children: [
              _buildSegmentedControl().marginOnly(bottom: 24),
              if (graphType == GraphType.allTime) FadeIn(key: const Key('1'), child: _AllTimeTable(galleryStats: galleryStats)),
              if (graphType == GraphType.year) FadeIn(key: const Key('2'), child: _LineGraph(datasource: galleryStats.yearlyStats)),
              if (graphType == GraphType.month) FadeIn(key: const Key('3'), child: _LineGraph(datasource: galleryStats.monthlyStats)),
              if (graphType == GraphType.day) FadeIn(key: const Key('4'), child: _LineGraph(datasource: galleryStats.dailyStats)),
            ],
          ),
          errorTapCallback: _getGalleryStats,
          noDataWidget: Text('invisible2UserWithoutDonation'.tr),
          noDataTapCallback: _getGalleryStats,
        ),
      ],
    );
  }

  Widget _buildSegmentedControl() {
    return CupertinoSlidingSegmentedControl<GraphType>(
      groupValue: graphType,
      children: {
        GraphType.allTime: Text('allTime'.tr).paddingSymmetric(horizontal: 12),
        GraphType.year: Text('year'.tr).paddingSymmetric(horizontal: 12),
        GraphType.month: Text('month'.tr).paddingSymmetric(horizontal: 12),
        GraphType.day: Text('day'.tr).paddingSymmetric(horizontal: 12),
      },
      onValueChanged: (value) => setState(() => graphType = value!),
    );
  }

  Future<void> _getGalleryStats() async {
    setState(() {
      loadingState = LoadingState.loading;
    });

    try {
      galleryStats = await ehRequest.requestStatPage(
        gid: widget.gid,
        token: widget.token,
        parser: EHSpiderParser.statPage2GalleryStats,
      );
    } on DioException catch (e) {
      log.error('getGalleryStatisticsFailed'.tr, e.errorMsg);
      snack('getGalleryStatisticsFailed'.tr, e.errorMsg ?? '');
      setStateSafely(() => loadingState = LoadingState.error);
      return;
    } on EHSiteException catch (e) {
      if (e.type == EHSiteExceptionType.galleryDeleted) {
        log.error('invisible2UserWithoutDonation'.tr);
        setStateSafely(() => loadingState = LoadingState.noData);
        return;
      }

      log.error('getGalleryStatisticsFailed'.tr, e.message);
      snack('getGalleryStatisticsFailed'.tr, e.message);
      setStateSafely(() => loadingState = LoadingState.error);
      return;
    } catch (e) {
      log.error('getGalleryStatisticsFailed'.tr, e.toString());
      snack('getGalleryStatisticsFailed'.tr, e.toString());
      setStateSafely(() => loadingState = LoadingState.error);
      return;
    }

    if (mounted) {
      setState(() {
        loadingState = LoadingState.success;
      });
    }
  }
}

class _AllTimeTable extends StatelessWidget {
  final GalleryStats galleryStats;

  const _AllTimeTable({Key? key, required this.galleryStats}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text('${'totalVisits'.tr}: ${galleryStats.totalVisits}', style: const TextStyle(fontWeight: FontWeight.bold)),
        DataTable(
          columnSpacing: UIConfig.statisticsDialogColumnSpacing,
          columns: <DataColumn>[
            DataColumn(
              label: SizedBox(width: UIConfig.statisticsDialogColumnWidth, child: Center(child: Text('period'.tr))),
            ),
            DataColumn(
              label: SizedBox(width: UIConfig.statisticsDialogColumnWidth, child: Center(child: Text('ranking'.tr))),
            ),
            DataColumn(
              label: SizedBox(width: UIConfig.statisticsDialogColumnWidth, child: Center(child: Text('score'.tr))),
            ),
          ],
          rows: <DataRow>[
            DataRow(
              cells: <DataCell>[
                DataCell(Center(child: Text('allTime'.tr))),
                DataCell(Center(child: Text(galleryStats.allTimeRanking == null ? '-' : '#${galleryStats.allTimeRanking}'))),
                DataCell(Center(child: Text(galleryStats.allTimeScore == null ? '-' : galleryStats.allTimeScore.toString()))),
              ],
            ),
            DataRow(
              cells: <DataCell>[
                DataCell(Center(child: Text('year'.tr))),
                DataCell(Center(child: Text(galleryStats.yearRanking == null ? '-' : '#${galleryStats.yearRanking}'))),
                DataCell(Center(child: Text(galleryStats.yearScore == null ? '-' : galleryStats.yearScore.toString()))),
              ],
            ),
            DataRow(
              cells: <DataCell>[
                DataCell(Center(child: Text('month'.tr))),
                DataCell(Center(child: Text(galleryStats.monthRanking == null ? '-' : '#${galleryStats.monthRanking}'))),
                DataCell(Center(child: Text(galleryStats.monthScore == null ? '-' : galleryStats.monthScore.toString()))),
              ],
            ),
            DataRow(
              cells: <DataCell>[
                DataCell(Center(child: Text('day'.tr))),
                DataCell(Center(child: Text(galleryStats.dayRanking == null ? '-' : '#${galleryStats.dayRanking}'))),
                DataCell(Center(child: Text(galleryStats.dayScore == null ? '-' : galleryStats.dayScore.toString()))),
              ],
            ),
          ],
        ).marginOnly(top: 4),
      ],
    );
  }
}

// GPL-3.0-only derivative change: use Flutter canvas instead of Syncfusion.
class _LineGraph extends StatelessWidget {
  final List<VisitStat> datasource;
  const _LineGraph({Key? key, required this.datasource}) : super(key: key);
  @override
  Widget build(BuildContext context) => SizedBox(
    height: UIConfig.statisticsDialogGraphHeight,
    width: UIConfig.statisticsDialogGraphWidth,
    child: NativeVisitChart(data: datasource),
  );
}
