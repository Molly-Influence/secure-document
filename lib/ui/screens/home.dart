import 'dart:developer';
import 'dart:io';

import 'package:auto_size_text/auto_size_text.dart';
import 'package:file_selector/file_selector.dart';
import 'package:ez_validator/validator/ez_validator_builder.dart';
import 'package:flutter/material.dart';
import 'package:website_cloner/constant/regex_list.dart';
import 'package:website_cloner/data/network/dio/dio_handler.dart';
import 'package:website_cloner/models/media_type.dart';
import 'package:website_cloner/ui/screens/headers.dart';
import 'package:website_cloner/utils/media_identifier.dart';
import 'package:website_cloner/utils/app_utils/widget_extensions.dart';
import 'package:website_cloner/utils/modals/app_modals.dart';
import 'package:website_cloner/widgets/winform.dart';

enum ContentStatus {
  pending(Colors.orange),
  success(Colors.green),
  error(Colors.red);

  final Color color;
  const ContentStatus(this.color);
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  HomePageState createState() => HomePageState();
}

class HomePageState extends State<HomePage> {
  final urlValidator = EzValidator().url().build();
  final TextEditingController urlController = TextEditingController();
  bool isLoading = false;
  bool isDownloading = false;
  late String? saveDirectory;
  ValueNotifier<Map<MediaModel, ContentStatus>> mediaList =
      ValueNotifier<Map<MediaModel, ContentStatus>>({});
  final TextEditingController headersController = TextEditingController();

  void showSettingsDialog() {
    showDialog(
      context: context,
      builder: ((context) => StatefulBuilder(builder: (context, setter) {
            return AlertDialog(
              backgroundColor: Colors.transparent,
              elevation: 0.0,
              contentPadding: EdgeInsets.zero,
              content: HeadersText(
                controller: headersController,
                onSubmit: () {
                  Map<String, String> headers = {};
                  log('headers: ${headersController.text}');
                  if (headersController.text.isNotEmpty) {
                    headersController.text.split('\n').forEach((e) {
                      final header = e.split(':');
                      headers[header.first] = header.last;
                    });
                  }
                  DioHandler.headers = headers;
                  log('headers: ${DioHandler.headers}');
                  Navigator.pop(context);
                },
              ),
            );
          })),
    );
  }

  void setLoading(bool value) {
    setState(() {
      isLoading = value;
    });
  }

  void setDownloading(bool value) {
    setState(() {
      isDownloading = value;
    });
  }

  void getContent() async {
    mediaList.value.clear();
    saveDirectory = await getDirectoryPath();
    if (saveDirectory == null) return;
    setLoading(true);
    Directory(saveDirectory!)
        .create(recursive: true)
        .then((Directory directory) {
      log('Directory created at: ${directory.path}');
    });
    DioHandler.getWebsiteContent(urlController.text).then((response) async {
      File('$saveDirectory/index.html').writeAsString(response).then((value) {
        log('index written');
      });
      RegExp(mediaRegex).allMatches(response).forEach((match) {
        if ((match.group(3) != null) &&
            urlValidator(match.group(3)!) != null &&
            isValidMedia(match.group(3)!)) {
          final model = MediaModel.fromRegex(match);
          log('message: $model \n', name: 'MATCHED-ASSETS');
          mediaList.value[model] = ContentStatus.pending;
        }
      });
      setLoading(false);
    }).catchError((error) {
      log('$error');
      setLoading(false);
    });
  }

  Future<void> downloadContent() async {
    setDownloading(true);
    await Future.forEach<MediaModel>(mediaList.value.keys.map((e) => e),
        (media) async {
      final path = await Directory('$saveDirectory/${media.folderPath}')
          .create(recursive: true);
      log('path: ${path.path}');
      try {
        await DioHandler.downloadFile(
          '${urlCleaner(urlController.text)}${schemaCleaner(media.mediaPath!)}',
          '${path.path}${media.fileName}',
        );
        mediaList.value[media] = ContentStatus.success;
      } catch (e) {
        log('$e', name: 'DOWNLOAD-ERROR');
        mediaList.value[media] = ContentStatus.error;
      }
    });
    setDownloading(false);
    if (mounted) {
      Toastr.showSuccessModal(context, 'Download Complete');
    }
  }
  //https://arbal.github.io/awesome-stars/assets/css/style.css?v=f9c04711779e7c206691b7d040ca8f9e899526f8

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: MainWinForm(
        child: Column(
          children: [
            const SizedBox(height: 10.0),
            Row(
              children: [
                Flexible(
                  child: TextFormField(
                    controller: urlController,
                    decoration: InputDecoration(
                      hintText: 'Enter URL',
                      prefixIcon: const Icon(
                        Icons.link,
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderSide: BorderSide(color: Color(0xFFd0d6db)),
                      ),
                      border: InputBorder.none,
                      fillColor: const Color(0xFFd0d6db).withOpacity(.3),
                      filled: true,
                    ),
                    validator: EzValidator().required().url().build(),
                  ),
                ),
                IconButton(
                  onPressed: () {
                    showSettingsDialog();
                  },
                  icon: Icon(
                    Icons.settings,
                    color: Theme.of(context).colorScheme.secondary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10.0),
            downloadButton(),
            const SizedBox(height: 10.0),
            Expanded(child: contentList())
          ],
        ).paddingHV(h: 25.0),
      ),
      floatingActionButton:
          ValueListenableBuilder<Map<MediaModel, ContentStatus>>(
        valueListenable: mediaList,
        builder: ((_, value, __) => value.isEmpty
            ? const SizedBox.shrink()
            : FloatingActionButton(
                backgroundColor: Theme.of(context).colorScheme.primary,
                onPressed: () async {
                  if (isDownloading) return;
                  await downloadContent();
                },
                child: isDownloading
                    ? const SizedBox(
                        height: 25.0,
                        width: 25.0,
                        child: CircularProgressIndicator(color: Colors.white),
                      )
                    : const Icon(
                        Icons.download,
                      ),
              )),
      ),
    );
  }

  Widget downloadButton() => SizedBox(
        width: MediaQuery.of(context).size.width * .35,
        height: 35.0,
        child: TextButton.icon(
          style: TextButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.primary,
          ),
          onPressed: () {
            if (isLoading) return;
            if (urlValidator(urlController.text) != null) {
              Toastr.showStaticModal(
                context,
                'Error',
                'Please enter a valid URL',
              );
              return;
            }
            getContent();
          },
          icon: const Icon(Icons.download, color: Colors.white)
              .visibleWhen(!isLoading),
          label: isLoading
              ? const SizedBox(
                  width: 20.0,
                  height: 20.0,
                  child: CircularProgressIndicator(color: Colors.white),
                )
              : const Text(
                  'Download',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
        ),
      );

  Widget contentList() {
    return ValueListenableBuilder<Map<MediaModel, ContentStatus>>(
      valueListenable: mediaList,
      builder: (_, value, __) {
        return value.isEmpty
            ? Center(
                child: Text(
                  'There are no assets to download',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              )
            : ListView.separated(
                separatorBuilder: (_, __) => const Divider(),
                shrinkWrap: true,
                itemCount: value.length,
                itemBuilder: (_, index) {
                  final item = value.keys.elementAt(index);
                  final status = value.values.elementAt(index);
                  return ListTile(
                    title: AutoSizeText(
                      item.fileName,
                      maxLines: 2,
                      style: const TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    trailing: Text(
                      status.name,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: status.color,
                      ),
                    ),
                    subtitle: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              vertical: 5, horizontal: 10.0),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .secondary
                                .withOpacity(.5),
                            borderRadius: BorderRadius.circular(15.0),
                          ),
                          child: Text(
                            item.mediaType!.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ).paddingLRTB(t: 5.0),
                    leading: Icon(
                      getIconByMediaType(item.mediaType!),
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  );
                },
              );
      },
    );
  }
}
