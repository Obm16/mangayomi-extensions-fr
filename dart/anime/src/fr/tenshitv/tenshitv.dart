import 'package:mangayomi/bridge_lib.dart';
import 'dart:convert';

// TenshiTV (https://tenshitv.com) - VOSTFR/VF
// ATTENTION : le site est derriere Cloudflare. L'app MangaYomi passe
// l'intermediaire (hasCloudflare: true) mais les selecteurs ci-dessous
// sont a verifier/ajuster avec l'editeur de code integre de l'app
// (Extensions -> source -> Edit code -> Fetch result).

class TenshiTV extends MProvider {
  TenshiTV({required this.source});

  MSource source;

  final Client client = Client();

  @override
  String get baseUrl {
    String pref = getPreferenceValue(source.id, "overrideBaseUrl") ?? "";
    pref = pref.trim();
    if (pref.isEmpty) pref = "https://tenshitv.com";
    if (pref.endsWith("/")) pref = pref.substring(0, pref.length - 1);
    return pref;
  }

  Map<String, String> get _headers => {
        "Referer": "$baseUrl/",
        "User-Agent":
            "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/126.0 Safari/537.36",
        "X-Requested-With": "XMLHttpRequest",
      };

  // ============================== Popular ===============================
  @override
  Future<MPages> getPopular(int page) async {
    final res =
        (await client.get(Uri.parse("$baseUrl/animes?page=$page"), headers: _headers))
            .body;
    return _parseGrid(res);
  }

  // =============================== Latest ===============================
  @override
  Future<MPages> getLatestUpdates(int page) async {
    final res = (await client.get(Uri.parse("$baseUrl/?page=$page"), headers: _headers))
        .body;
    return _parseGrid(res);
  }

  // =============================== Search ===============================
  @override
  Future<MPages> search(String query, int page, FilterList filterList) async {
    final res = (await client
            .get(Uri.parse("$baseUrl/animes?search=${Uri.encodeComponent(query)}&page=$page"),
                headers: _headers))
        .body;
    return _parseGrid(res);
  }

  // Grille d'animes : cartes <a> avec <img> et un titre
  MPages _parseGrid(String res) {
    List<MManga> animeList = [];
    final urls = xpath(res, '//a[contains(@href,"/anime/")]/@href');
    final names = xpath(res, '//a[contains(@href,"/anime/")]//h3/text()');
    final namesAlt = xpath(res, '//a[contains(@href,"/anime/")]/@title');
    final images = xpath(res, '//a[contains(@href,"/anime/")]//img/@src');

    for (var i = 0; i < urls.length; i++) {
      MManga anime = MManga();
      anime.name = i < names.length && names[i].trim().isNotEmpty
          ? names[i].trim()
          : (i < namesAlt.length ? namesAlt[i] : "");
      anime.imageUrl = i < images.length ? images[i] : "";
      anime.link = urls[i].startsWith("http") ? urls[i] : "$baseUrl$urls[i]";
      if (anime.name.isNotEmpty) animeList.add(anime);
    }
    final nextPage = xpath(
        res, '//a[(@rel="next" or contains(@class,"next") or contains(text(),"Suivant"))]/@href');
    return MPages(animeList, nextPage.isNotEmpty);
  }

  // =========================== Anime Details ============================
  @override
  Future<MManga> getDetail(String url) async {
    final statusList = [
      {"En cours": 0, "Terminé": 1, "Abandonné": 3, "En pause": 2},
    ];

    final res = (await client.get(Uri.parse(url), headers: _headers)).body;
    MManga anime = MManga();

    final description = xpath(
      res,
      '//meta[@name="description"]/@content | //meta[@property="og:description"]/@content',
    );
    if (description.isNotEmpty) anime.description = description.first;

    final status = xpath(
      res,
      '//*[contains(text(),"Statut") or contains(text(),"Status")]/following-sibling::*[1]/text()',
    );
    if (status.isNotEmpty) {
      anime.status = parseStatus(status.first.trim(), statusList);
    }

    anime.genre = xpath(res, '//a[contains(@href,"genre")]/text()')
        .map((g) => g.trim())
        .toList();

    // Liens des episodes : adapte le selecteur a la vraie page
    final epUrls = xpath(
      res,
      '//a[contains(@href,"episode") or contains(@href,"ep-")]/@href',
    );
    final epNames = xpath(
      res,
      '//a[contains(@href,"episode") or contains(@href,"ep-")]/text()',
    );

    List<MChapter>? episodesList = [];
    for (var i = 0; i < epUrls.length; i++) {
      final num = regExp(epNames.length > i ? epNames[i] : epUrls[i], r'(\d+)', '', 1, 1);
      MChapter episode = MChapter();
      episode.name = "Épisode $num";
      episode.url =
          epUrls[i].startsWith("http") ? epUrls[i] : "$baseUrl${epUrls[i]}";
      episodesList.add(episode);
    }

    anime.chapters = episodesList;
    return anime;
  }

  // ============================ Video Extractor =============================
  @override
  Future<List<MVideo>> getVideoList(String url) async {
    final res = (await client.get(Uri.parse(url), headers: _headers)).body;
    final hosterSelection = preferenceHosterSelection(source.id);

    final iframes = xpath(res, '//iframe/@src');
    List<MVideo> videos = [];
    for (var embedUrl in iframes) {
      if (embedUrl == "about:blank") continue;
      if (!embedUrl.startsWith("http")) embedUrl = "https:$embedUrl";
      List<MVideo> a = [];
      final lower = embedUrl.toLowerCase();
      if (lower.contains("sibnet") && hosterSelection.contains("Sibnet")) {
        a = await sibnetExtractor(embedUrl, "");
      } else if (lower.contains("sendvid") && hosterSelection.contains("Sendvid")) {
        a = await sendvidExtractor(embedUrl, "");
      } else if ((lower.contains("voe") || lower.contains("voembed")) &&
          hosterSelection.contains("Voe")) {
        a = await voeExtractor(embedUrl, "");
      } else if (lower.contains("filemoon") || RegExp(r'mfw\d+').hasMatch(lower)) {
        a = await filemoonExtractor(embedUrl, "Filemoon", "");
      } else if (lower.contains("streamtape") && hosterSelection.contains("Streamtape")) {
        a = await streamTapeExtractor(embedUrl, null);
      } else if (lower.contains("dood") && hosterSelection.contains("Doodstream")) {
        a = await doodExtractor(embedUrl, null);
      } else if (lower.contains("streamwish") && hosterSelection.contains("Streamwish")) {
        a = await streamWishExtractor(embedUrl, "StreamWish");
      } else if (lower.contains("vidmoly")) {
        a = await vidmolyExtractor(embedUrl, "");
      }
      videos.addAll(a);
    }

    final seenUrls = <String>{};
    return videos.where((v) => seenUrls.add(v.url.split("?").first)).toList();
  }

  // ============================ Extractors =============================
  Future<List<MVideo>> sendvidExtractor(String url, String prefix) async {
    final res = (await client.get(Uri.parse(url), headers: _headers)).body;
    final document = parseHtml(res);
    final masterUrl = document.selectFirst("source#video_source")?.attr("src");
    if (masterUrl == null) return [];
    final origin = "https://${Uri.parse(url).host}";
    final headers = {"Origin": origin, "Referer": "$origin/"};
    List<MVideo> videos = [];
    if (masterUrl.contains(".m3u8")) {
      final playlist = (await client.get(Uri.parse(masterUrl), headers: headers)).body;
      for (var it in substringAfter(playlist, "#EXT-X-STREAM-INF:")
          .split("#EXT-X-STREAM-INF:")) {
        final resMatch = RegExp(r"RESOLUTION=\d+x(\d+)").firstMatch(it);
        final quality = resMatch != null ? "${resMatch.group(1)}p" : "720p";
        String videoUrl = substringBefore(substringAfter(it, "\n"), "\n").trim();
        if (!videoUrl.startsWith("http")) {
          videoUrl = "${masterUrl.substring(0, masterUrl.lastIndexOf('/'))}/$videoUrl";
        }
        var v = MVideo();
        v..url = videoUrl
          ..originalUrl = videoUrl
          ..quality = "${prefix}Sendvid:$quality"
          ..headers = headers;
        videos.add(v);
      }
    } else {
      var v = MVideo();
      v..url = masterUrl
        ..originalUrl = masterUrl
        ..quality = "${prefix}Sendvid:default"
        ..headers = headers;
      videos.add(v);
    }
    return videos;
  }

  Future<List<MVideo>> vidmolyExtractor(String url, String prefix) async {
    const vidmolyBase = "https://vidmoly.biz";
    final fixedUrl = url.startsWith(vidmolyBase)
        ? url
        : url.replaceFirst(
            RegExp(r"^https?://(?:www\.)?[^/]+/"), "$vidmolyBase/");
    final headers = {
      "Origin": vidmolyBase,
      "Referer": "$vidmolyBase/",
      "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36",
    };
    final res = (await client.get(Uri.parse(fixedUrl), headers: headers)).body;
    final fileMatch = RegExp(
            r"""file\s*:\s*["']?(https?://[^"']+\.m3u8[^"']*)["']?""")
        .firstMatch(res);
    if (fileMatch != null) {
      final m3u8Url = fileMatch.group(1)!;
      var v = MVideo();
      v..url = m3u8Url
        ..originalUrl = m3u8Url
        ..quality = "${prefix}VidMoly - 1080p"
        ..headers = headers;
      return [v];
    }
    return [];
  }

  // ============================ Preferences =============================
  @override
  List<dynamic> getSourcePreferences() {
    return [
      EditTextPreference(
        key: "overrideBaseUrl",
        title: "Changer l'url de base",
        summary: "En cas de changement de domaine (ex: https://tenshitv.com)",
        value: "https://tenshitv.com",
        dialogTitle: "Changer l'url de base",
        dialogMessage: "",
        text: "https://tenshitv.com",
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
          "Sibnet", "Sendvid", "Voe", "Streamtape", "Doodstream", "Streamwish",
        ],
        entryValues: [
          "Sibnet", "Sendvid", "Voe", "Streamtape", "Doodstream", "Streamwish",
        ],
        values: [
          "Sibnet", "Sendvid", "Voe", "Streamtape", "Doodstream", "Streamwish",
        ],
      ),
    ];
  }

  @override
  List<dynamic> getFilterList() {
    return [
      HeaderFilter("La recherche de texte ignore les filtres"),
    ];
  }
}

TenshiTV main(MSource source) {
  return TenshiTV(source: source);
}
