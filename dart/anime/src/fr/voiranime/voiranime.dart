import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

class VoirAnime extends MProvider {
  VoirAnime({required this.source});

  MSource source;

  final Client client = Client();

  @override
  String get baseUrl {
    String pref = getPreferenceValue(source.id, "overrideBaseUrl") ?? "";
    pref = pref.trim();
    if (pref.isEmpty) pref = "https://voir-anime.to";
    if (pref.endsWith("/")) pref = pref.substring(0, pref.length - 1);
    return pref;
  }

  // ============================== Popular ===============================
  @override
  Future<MPages> getPopular(int page) async {
    final url =
        "$baseUrl/liste-danimes/${page > 1 ? "page/$page/" : ""}?m_orderby=popular";
    final res = (await client.get(Uri.parse(url))).body;
    return _parseListing(res);
  }

  // =============================== Latest ===============================
  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res =
        (await client.get(Uri.parse("$baseUrl/nouveaux-ajouts/page/$page/")))
            .body;
    return _parseListing(res);
  }

  // =============================== Search ===============================
  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    String url;
    if (query.isNotEmpty) {
      url =
          "$baseUrl/page/$page/?s=${Uri.encodeComponent(query)}&post_type=wp-manga";
    } else {
      String genre = "";
      String orderby = "popular";
      for (var filter in filterList.filters) {
        if (filter.type == "GenreFilter" && filter.state != 0) {
          genre = filter.values[filter.state].value;
        } else if (filter.type == "OrderByFilter" && filter.state != 0) {
          orderby = filter.values[filter.state].value;
        }
      }
      if (genre.isNotEmpty) {
        url =
            "$baseUrl/anime-genre/$genre/${page > 1 ? "page/$page/" : ""}?m_orderby=$orderby";
      } else {
        url =
            "$baseUrl/liste-danimes/${page > 1 ? "page/$page/" : ""}?m_orderby=$orderby";
      }
    }
    final res = (await client.get(Uri.parse(url))).body;
    return _parseListing(res);
  }

  List<MManga> parseContainer(String res, String containerClass) {
    List<MManga> animeList = [];
    final urls = xpath(
      res,
      '//div[contains(@class,"$containerClass")]//h3/a/@href',
    );
    final names = xpath(
      res,
      '//div[contains(@class,"$containerClass")]//h3/a/text()',
    );
    final images = xpath(
      res,
      '//div[contains(@class,"$containerClass")]//img/@data-src',
    );
    final imagesAlt = xpath(
      res,
      '//div[contains(@class,"$containerClass")]//img/@src',
    );

    for (var i = 0; i < names.length; i++) {
      MManga anime = MManga();
      anime.name = names[i].trim();
      anime.imageUrl =
          images.length > i ? images[i] : (imagesAlt.length > i ? imagesAlt[i] : "");
      anime.link = urls[i];
      animeList.add(anime);
    }
    return animeList;
  }

  MPages _parseListing(String res) {
    List<MManga> animeList = [
      ...parseContainer(res, "page-item-detail"),
      ...parseContainer(res, "c-tabs-item__content"),
    ];
    final nextPage = xpath(res, '//a[@class="next page-numbers"]/@href');
    return MPages(animeList, nextPage.isNotEmpty);
  }

  // =========================== Anime Details ============================
  @override
  Future<MManga> getDetail(String url) async {
    final statusList = [
      {"En cours": 0, "Completed": 1, "Terminé": 1, "On hiatus": 2, "Canceled": 3},
    ];

    final res = (await client.get(Uri.parse(url))).body;
    MManga anime = MManga();

    final description = xpath(
      res,
      '//div[contains(@class,"summary__content")]//p/text()',
    );
    if (description.isNotEmpty) {
      anime.description = description.join(" ").trim();
    } else {
      final alt = xpath(res, '//meta[@name="description"]/@content');
      if (alt.isNotEmpty) anime.description = alt.first;
    }

    final status = xpath(
      res,
      '//div[contains(@class,"post-status")]//div[@class="summary-content" and (contains(text(),"En cours") or contains(text(),"Completed") or contains(text(),"Terminé"))]/text()',
    );
    if (status.isNotEmpty) {
      anime.status = parseStatus(status.first.trim(), statusList);
    }

    anime.genre =
        xpath(res, '//a[contains(@href,"anime-genre")]/text()')
            .map((g) => g.trim())
            .toList();

    final epUrls = xpath(
      res,
      '//li[contains(@class,"wp-manga-chapter")]/a/@href',
    );
    final epNames = xpath(
      res,
      '//li[contains(@class,"wp-manga-chapter")]/a/text()',
    );

    List<MChapter>? episodesList = [];
    for (var i = 0; i < epUrls.length; i++) {
      MChapter episode = MChapter();
      final num = regExp(epNames[i], r'(\d+)', '', 1, 1);
      episode.name = "Épisode $num";
      episode.url = epUrls[i];
      episodesList.add(episode);
    }

    anime.chapters = episodesList;
    return anime;
  }

  // ============================ Video Extractor =============================
  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final hosterSelection = preferenceHosterSelection(source.id);
    List<MVideo> videos = [];

    final resHosts =
        (await client.get(Uri.parse(url))).body;
    final hosts = xpath(
      resHosts,
      '//select//option[contains(@value,"LECTEUR")]/@value',
    );

    for (var host in hosts) {
      final hostUrl =
          "$baseUrl${getUrlWithoutDomain(url)}?host=${Uri.encodeComponent(host)}";
      try {
        final res =
            (await client.get(Uri.parse(hostUrl))).body;
        final iframes = xpath(res, '//iframe/@src');
        if (iframes.isEmpty) continue;
        final embedUrl = iframes.first;
        List<MVideo> a = [];
        final lower = embedUrl.toLowerCase();
        if ((lower.contains("voe") || lower.contains("voembed")) &&
            hosterSelection.contains("Voe")) {
          a = await voeExtractor(embedUrl, "");
        } else if ((lower.contains("filemoon") ||
                lower.contains("moon") ||
                RegExp(r'mfw\d+').hasMatch(lower)) &&
            hosterSelection.contains("Filemoon")) {
          a = await filemoonExtractor(embedUrl, "");
        } else if (lower.contains("streamtape") &&
            hosterSelection.contains("Streamtape")) {
          a = await streamTapeExtractor(embedUrl);
        } else if ((lower.contains("myvi") || lower.contains("mytv")) &&
            hosterSelection.contains("MyTV")) {
          a = await myTvExtractor(embedUrl);
        } else if (lower.contains("sibnet") &&
            hosterSelection.contains("Sibnet")) {
          a = await sibnetExtractor(embedUrl, "");
        } else if (lower.contains("dood") &&
            hosterSelection.contains("Doodstream")) {
          a = await doodExtractor(embedUrl);
        } else if ((lower.contains("streamwish") ||
                lower.contains("streamhide") ||
                lower.contains("awish") ||
                lower.contains("swhoi") ||
                lower.contains("mulwish")) &&
            hosterSelection.contains("Streamwish")) {
          a = await streamWishExtractor(embedUrl, "StreamWish");
        } else if (lower.contains("mail.ru") &&
            hosterSelection.contains("Okru")) {
          a = await okruExtractor(embedUrl);
        } else if (lower.contains("yourupload") &&
            hosterSelection.contains("YourUpload")) {
          a = await yourUploadExtractor(embedUrl, null, "YourUpload", "");
        }
        videos.addAll(a);
      } catch (_) {}
    }

    final seenUrls = <String>{};
    final uniqueVideos = <MVideo>[];
    for (var v in videos) {
      if (seenUrls.add(v.url.split("?").first)) {
        uniqueVideos.add(v);
      }
    }

    return sortVideos(uniqueVideos, source.id);
  }

  // ============================ Utilities =============================
  String fixUrl(String url) {
    return regExp(url, r"^(?:(?:https?:)?//|www\.)", "https://", 0, 0);
  }

  List<String> preferenceHosterSelection(int sourceId) {
    final value = getPreferenceValue(sourceId, "hoster_selection_");
    if (value is List) {
      final selection = value.map((e) => e.toString()).toList();
      if (selection.isNotEmpty) return selection;
    }
    return [
      "Voe", "Filemoon", "Streamtape", "MyTV", "Sibnet", "Doodstream",
      "Streamwish", "Okru", "YourUpload",
    ];
  }

  List<MVideo> sortVideos(List<MVideo> videos, int sourceId) {
    String quality = getPreferenceValue(sourceId, "preferred_quality") ?? "";
    videos.sort((MVideo a, MVideo b) {
      int qualityMatchA = a.quality.contains(quality) ? 1 : 0;
      int qualityMatchB = b.quality.contains(quality) ? 1 : 0;
      if (qualityMatchA != qualityMatchB) return qualityMatchB - qualityMatchA;

      final regex = RegExp(r'(\d+)p');
      final matchA = regex.firstMatch(a.quality);
      final matchB = regex.firstMatch(b.quality);
      final int qualityNumA = int.tryParse(matchA?.group(1) ?? '0') ?? 0;
      final int qualityNumB = int.tryParse(matchB?.group(1) ?? '0') ?? 0;
      return qualityNumB - qualityNumA;
    });
    return videos;
  }

  // ============================ Preferences & Filters =============================
  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key: "overrideBaseUrl",
        title: "Changer l'url de base",
        summary: "En cas de changement de domaine (ex: https://voir-anime.to)",
        value: "https://voir-anime.to",
        dialogTitle: "Changer l'url de base",
        dialogMessage: "",
        text: "https://voir-anime.to",
      ),
      ListPreference(
        key: "preferred_quality",
        title: "Qualité préférée",
        summary: "",
        valueIndex: 0,
        entries: ["1080p", "720p", "480p", "360p"],
        entryValues: ["1080", "720", "480", "360"],
      ),
      MultiSelectListPreference(
        key: "hoster_selection_",
        title: "Activer/Désactiver les hébergeurs",
        summary: "",
        entries: [
          "Voe", "Filemoon", "Streamtape", "MyTV", "Sibnet", "Doodstream",
          "Streamwish", "Okru", "YourUpload",
        ],
        entryValues: [
          "Voe", "Filemoon", "Streamtape", "MyTV", "Sibnet", "Doodstream",
          "Streamwish", "Okru", "YourUpload",
        ],
        values: [
          "Voe", "Filemoon", "Streamtape", "MyTV", "Sibnet", "Doodstream",
          "Streamwish", "Okru", "YourUpload",
        ],
      ),
    ];
  }

  @override
  List<dynamic> getFilterList() {
    return [
      HeaderFilter("La recherche de texte ignore les filtres"),
      SelectFilter("OrderByFilter", "Trier par", 0, [
        SelectFilterOption("<Sélectionner>", ""),
        SelectFilterOption("Populaire", "popular"),
        SelectFilterOption("Récent", "latest"),
        SelectFilterOption("A-Z", "alphabet"),
        SelectFilterOption("Note", "rating"),
      ]),
      SelectFilter("GenreFilter", "Genre", 0, [
        SelectFilterOption("<Sélectionner>", ""),
        SelectFilterOption("Action", "action"),
        SelectFilterOption("Aventure", "adventure"),
        SelectFilterOption("Comédie", "comedy"),
        SelectFilterOption("Drame", "drama"),
        SelectFilterOption("Fantasy", "fantasy"),
        SelectFilterOption("Horreur", "horror"),
        SelectFilterOption("Mecha", "mecha"),
        SelectFilterOption("Mystère", "mystery"),
        SelectFilterOption("Psychologique", "psychological"),
        SelectFilterOption("Romance", "romance"),
        SelectFilterOption("Sci-Fi", "sci-fi"),
        SelectFilterOption("Sport", "sports"),
        SelectFilterOption("Surnaturel", "supernatural"),
        SelectFilterOption("Tranche de vie", "slice-of-life"),
      ]),
    ];
  }
}

VoirAnime main(MSource source) {
  return VoirAnime(source: source);
}
