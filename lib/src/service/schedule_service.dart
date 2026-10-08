// Modified for Bilingual Lite (2026-10-07); see NOTICE. Original JHenTai portions: Apache-2.0.
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart';
import 'package:extended_image/extended_image.dart';
import 'package:get/get_rx/get_rx.dart';
import 'package:get/get_utils/get_utils.dart';
import 'package:jhentai/src/database/dao/archive_dao.dart';
import 'package:jhentai/src/database/dao/gallery_dao.dart';
import 'package:jhentai/src/extension/dio_exception_extension.dart';
import 'package:jhentai/src/network/eh_request.dart';
import 'package:jhentai/src/setting/archive_bot_setting.dart';
import 'package:jhentai/src/setting/network_setting.dart';
import 'package:jhentai/src/setting/preference_setting.dart';
import 'package:jhentai/src/setting/user_setting.dart';
import 'package:jhentai/src/utils/convert_util.dart';
import 'package:jhentai/src/utils/eh_spider_parser.dart';
import 'package:jhentai/src/utils/snack_util.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:retry/retry.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../database/database.dart';
import '../enum/config_enum.dart';
import '../model/archive_bot_response/archive_bot_response.dart';
import '../model/gallery_metadata.dart';
import '../network/archive_bot_request.dart';
import 'jh_service.dart';
import 'log.dart';

ScheduleService scheduleService = ScheduleService();

class ScheduleService
    with JHLifeCircleBeanErrorCatch
    implements JHLifeCircleBean {
  @override
  Future<void> doInitBean() async {}

  @override
  Future<void> doAfterBeanReady() async {
    Timer(const Duration(seconds: 10), refreshGalleryTags);
    Timer(const Duration(seconds: 10), refreshArchiveTags);
    Timer(const Duration(seconds: 5), clearOutdatedImageCache);
    Timer(const Duration(seconds: 1), _clearOutdatedGalleryImageHashCache);

    Timer(const Duration(seconds: 5), checkEHEvent);
    Timer.periodic(const Duration(minutes: 5), (_) => checkEHEvent());

    if (archiveBotSetting.botType.value.supportsCheckIn) {
      Timer(const Duration(seconds: 5), checkInArchiveBot);
      Timer.periodic(const Duration(minutes: 5), (_) => checkInArchiveBot());
    }
  }

  Future<void> refreshGalleryTags() async {
    int pageNo = 1;
    List<GalleryDownloadedData> galleries =
        await GalleryDao.selectGalleriesForTagRefresh(pageNo, 25);
    while (galleries.isNotEmpty) {
      try {
        List<GalleryMetadata> metadatas =
            await ehRequest.requestGalleryMetadatas<List<GalleryMetadata>>(
          list: galleries.map((a) => (gid: a.gid, token: a.token)).toList(),
          parser: EHSpiderParser.galleryMetadataJson2GalleryMetadatas,
        );

        await GalleryDao.batchUpdateGallery(
          metadatas
              .map(
                (m) => GalleryDownloadedCompanion(
                  gid: Value(m.galleryUrl.gid),
                  tags: Value(tagMap2TagString(m.tags)),
                  tagRefreshTime: Value(DateTime.now().toString()),
                ),
              )
              .toList(),
        );
        log.trace(
            'refreshGalleryTags success, pageNo: $pageNo, archives: ${galleries.map((a) => a.gid).toList()}');
      } catch (e) {
        log.warning(
            'refreshGalleryTags error, galleries: ${galleries.map((a) => (
                  gid: a.gid,
                  token: a.token
                )).toList()}',
            e,
            true);
      }

      pageNo++;
      galleries = await GalleryDao.selectGalleriesForTagRefresh(pageNo, 25);
    }
  }

  Future<void> refreshArchiveTags() async {
    int pageNo = 1;
    List<ArchiveDownloadedData> archives =
        await ArchiveDao.selectArchivesForTagRefresh(pageNo, 25);
    while (archives.isNotEmpty) {
      try {
        List<GalleryMetadata> metadatas =
            await ehRequest.requestGalleryMetadatas<List<GalleryMetadata>>(
          list: archives.map((a) => (gid: a.gid, token: a.token)).toList(),
          parser: EHSpiderParser.galleryMetadataJson2GalleryMetadatas,
        );

        await ArchiveDao.batchUpdateArchive(
          metadatas
              .map(
                (m) => ArchiveDownloadedCompanion(
                  gid: Value(m.galleryUrl.gid),
                  tags: Value(tagMap2TagString(m.tags)),
                  tagRefreshTime: Value(DateTime.now().toString()),
                ),
              )
              .toList(),
        );
        log.trace(
            'refreshArchiveTags success, pageNo: $pageNo, archives: ${archives.map((a) => a.gid).toList()}');
      } catch (e) {
        log.warning(
            'refreshArchiveTags error, archives: ${archives.map((a) => a.gid).toList()}',
            e,
            true);
      }

      pageNo++;
      archives = await ArchiveDao.selectArchivesForTagRefresh(pageNo, 25);
    }
  }

  Future<void> clearOutdatedImageCache() async {
    Directory cacheImageDirectory = Directory(
        join((await getTemporaryDirectory()).path, cacheImageFolderName));

    if (!cacheImageDirectory.existsSync()) {
      return;
    }

    int count = 0;
    cacheImageDirectory.list().forEach((FileSystemEntity entity) {
      if (entity is File &&
          DateTime.now().difference(entity.lastAccessedSync()) >
              networkSetting.cacheImageExpireDuration.value) {
        entity.delete();
        count++;
      }
    }).then(
        (_) => log.info('Clear outdated image cache success, count: $count'));
  }

  Future<void> _clearOutdatedGalleryImageHashCache() async {
    DateTime thresholdTime = DateTime.now().subtract(const Duration(days: 3));
    String thresholdTimeStr = thresholdTime.toString();

    return appDb.managers.localConfig
        .filter((config) =>
            config.configKey.equals(ConfigEnum.galleryImageHash.key) &
            config.utime.column.isSmallerThanValue(thresholdTimeStr))
        .delete()
        .then((value) => value > 0);
  }

  Future<void> checkEHEvent() async {
    if (!userSetting.hasLoggedIn()) {
      return;
    }

    if (preferenceSetting.showHVInfo.isFalse &&
        preferenceSetting.showDawnInfo.isFalse) {
      return;
    }

    ({String? dawnInfo, String? hvUrl}) eventInfo;
    try {
      eventInfo = await retry(
        () => ehRequest.requestNews(EHSpiderParser.newsPage2Event),
        retryIf: (e) => e is DioException,
        maxAttempts: 3,
      );
    } catch (e) {
      log.warning('ScheduleService checkDawn failed', e);
      return;
    }

    if (preferenceSetting.showDawnInfo.isTrue && eventInfo.dawnInfo != null) {
      log.info('Check dawn success: ${eventInfo.dawnInfo}');
      snack(
        'dawnOfaNewDay'.tr,
        eventInfo.dawnInfo!,
        isShort: false,
      );
    }

    if (preferenceSetting.showHVInfo.isTrue && eventInfo.hvUrl != null) {
      log.info('Encounter a monster: ${eventInfo.hvUrl}');
      snack(
        'encounterMonster'.tr,
        'encounterMonsterHint'.tr,
        onPressed: () => launchUrlString(eventInfo.hvUrl!,
            mode: LaunchMode.externalApplication),
        isShort: false,
      );
    }
  }

  Future<void> checkInArchiveBot() async {
    if (!archiveBotSetting.isReady) {
      return;
    }
    if (!archiveBotSetting.botType.value.supportsCheckIn) {
      return;
    }

    try {
      ArchiveBotResponse response = await archiveBotRequest.requestCheckIn(
        botType: archiveBotSetting.botType.value,
        apiAddress: archiveBotSetting.apiAddress.value!,
        apiKey: archiveBotSetting.apiKey.value!,
      );
      log.debug('Auto Checkin response: $response');
      if (response.isSuccess) {
        final checkInVO =
            archiveBotSetting.botType.value.parseCheckIn(response.data);
        snack(
            'checkInSuccess'.tr,
            'checkInSuccessHint'.trArgs(
                [checkInVO.getGP.toString(), checkInVO.currentGP.toString()]));
      }
    } on DioException catch (e) {
      log.error('Failed to auto checkin', e.errorMsg, e.stackTrace);
    } catch (e) {
      log.error('Failed to auto checkin', e.toString(), StackTrace.current);
    }
  }
}
