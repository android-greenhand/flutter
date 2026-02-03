import 'dart:developer' as dev;

import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import '../services/unified_article_service.dart';
import '../widgets/page_container.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:math';
import 'package:markdown/markdown.dart' as md;
import 'package:scroll_to_index/scroll_to_index.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';
import 'package:cached_network_image/cached_network_image.dart';

class GitHubArticlePage extends StatefulWidget {
  final String owner;
  final String repo;
  final String path;
  final String title;

  const GitHubArticlePage({
    super.key,
    required this.owner,
    required this.repo,
    required this.path,
    required this.title,
  });

  @override
  State<GitHubArticlePage> createState() => _GitHubArticlePageState();
}

class _GitHubArticlePageState extends State<GitHubArticlePage> {
  String? _content;
  String? _error;
  bool _isLoading = true;
  List<_HeadingInfo> _headings = [];
  final AutoScrollController _scrollController = AutoScrollController();
  final ScrollController _tocScrollController = ScrollController();
  double _scrollProgress = 0.0;
  late ThemeData _theme;
  bool _showTableOfContents = false;
  int _currentHeadingIndex = 0;
  DateTime? _lastUpdated;
  String _authorName = '';

  @override
  void initState() {
    super.initState();
    _loadContent();
    
    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final maxExtent = _scrollController.position.maxScrollExtent;
      if (maxExtent <= 0) return;
      
      final progress = _scrollController.offset / maxExtent;
      setState(() {
        _scrollProgress = progress.clamp(0.0, 1.0);
        _updateCurrentHeading();
      });
    });
  }
  
  @override
  void dispose() {
    _scrollController.dispose();
    _tocScrollController.dispose();
    super.dispose();
  }

  void _updateCurrentHeading() {
    if (_headings.isEmpty || !_scrollController.hasClients) return;
    
    for (int i = _headings.length - 1; i >= 0; i--) {
      if (_scrollController.offset >= _headings[i].position - 60) { // 60 is approx navbar height
        if (_currentHeadingIndex != i) {
          setState(() {
            _currentHeadingIndex = i;
          });
          
          // Auto-scroll table of contents
          if (_tocScrollController.hasClients) {
            _tocScrollController.animateTo(
              i * 40.0, // Approximate height of each TOC item
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeInOut,
            );
          }
        }
        break;
      }
    }
  }

  Future<void> _loadContent() async {
    try {
      final content = await UnifiedArticleService.getMarkdownContent(
        widget.owner,
        widget.repo,
        widget.path,
      );

      final commitInfo = await UnifiedArticleService.getFileCommitInfo(
        widget.owner,
        widget.repo,
        widget.path,
      );

      if (commitInfo != null) {
        _lastUpdated = DateTime.parse(commitInfo['date'] as String);
        _authorName = commitInfo['author'] as String;
      }

      _extractHeadings(content);

      if (mounted) {
        setState(() {
          _content = content;
          _isLoading = false;
        });
      }
    } catch (e) {
      dev.log('内容加载失败', name: 'GitHubArticlePage', error: e);
      if (mounted) {
        setState(() {
          _error = e.toString();
          _isLoading = false;
        });
      }
    }
  }
  
  void _extractHeadings(String content) {
    final headingRegExp = RegExp(r'^(#{1,6})\s+(.+)$', multiLine: true);
    final matches = headingRegExp.allMatches(content);
    
    final headings = <_HeadingInfo>[];
    
    for (final match in matches) {
      final level = match.group(1)!.length;
      final text = match.group(2)!;
      
      final position = _calculateHeadingPosition(content, match.start);
      
      headings.add(_HeadingInfo(
        text: text,
        level: level,
        position: position,
      ));
    }
    
    setState(() {
      _headings = headings;
    });
  }
  
  double _calculateHeadingPosition(String content, int startIndex) {
    // Approximate position based on character count
    // This is a rough estimation - in a real app you'd measure actual rendered height
    final precedingText = content.substring(0, startIndex);
    final lineCount = '\n'.allMatches(precedingText).length;
    
    // Rough estimation based on average line height
    return lineCount * 24.0;
  }
  
  Future<void> _scrollToHeading(int index) async {
    await _scrollController.scrollToIndex(
      index,
      preferPosition: AutoScrollPosition.begin,
      duration: const Duration(milliseconds: 500),
    );
    
    setState(() {
      _currentHeadingIndex = index;
      if (_showTableOfContents) {
        _showTableOfContents = false;
      }
    });
  }

  Widget _buildLoadingState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _theme.colorScheme.primaryContainer.withOpacity(0.5),
                shape: BoxShape.circle,
              ),
              child: CircularProgressIndicator(
                valueColor: AlwaysStoppedAnimation<Color>(
                  _theme.colorScheme.primary,
                ),
                strokeWidth: 3,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              '正在加载文章内容...',
              style: _theme.textTheme.titleMedium?.copyWith(
                color: _theme.colorScheme.onSurface.withOpacity(0.8),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _getRandomLoadingTip(),
              style: _theme.textTheme.bodyMedium?.copyWith(
                color: _theme.colorScheme.onSurface.withOpacity(0.6),
                fontStyle: FontStyle.italic,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              size: 64,
              color: _theme.colorScheme.error,
            ),
            const SizedBox(height: 24),
            Text(
              '加载失败',
              style: _theme.textTheme.headlineSmall?.copyWith(
                color: _theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _error ?? '无法加载文章内容，请稍后再试',
              style: _theme.textTheme.bodyLarge?.copyWith(
                color: _theme.colorScheme.onSurface.withOpacity(0.7),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton.icon(
              icon: const Icon(Icons.refresh),
              label: const Text('重新加载'),
              onPressed: _loadContent,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTableOfContents() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      width: _showTableOfContents ? 280 : 0,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 300),
        opacity: _showTableOfContents ? 1.0 : 0.0,
        child: _headings.isEmpty ? const SizedBox() : Card(
          elevation: 6, // 增加阴影效果
          shadowColor: Colors.black.withOpacity(0.2),
          margin: EdgeInsets.zero,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.only(
              topRight: Radius.circular(12),
              bottomRight: Radius.circular(12),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(Icons.list, color: _theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Text(
                      '目录',
                      style: _theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: _theme.colorScheme.primary,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () {
                        setState(() {
                          _showTableOfContents = false;
                        });
                      },
                      tooltip: '关闭目录',
                      padding: EdgeInsets.zero, // 减小按钮内边距
                      constraints: const BoxConstraints(), // 移除约束
                      visualDensity: VisualDensity.compact, // 使用紧凑布局
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: Builder(
                  builder: (context) {
                    // Only create Scrollbar and ListView when table of contents is visible
                    if (!_showTableOfContents) {
                      return const SizedBox();
                    }
                    
                    return Scrollbar(
                      controller: _tocScrollController,
                      thumbVisibility: true, // 始终显示滚动条
                      child: ListView.builder(
                        controller: _tocScrollController,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        itemCount: _headings.length,
                        itemBuilder: (context, index) {
                          final heading = _headings[index];
                          return InkWell(
                            onTap: () => _scrollToHeading(index),
                            child: Container(
                              padding: EdgeInsets.only(
                                left: 16.0 + (heading.level - 1) * 16.0,
                                right: 16.0,
                                top: 8.0,
                                bottom: 8.0,
                              ),
                              decoration: BoxDecoration(
                                color: _currentHeadingIndex == index 
                                    ? _theme.colorScheme.primaryContainer
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                heading.text,
                                style: _theme.textTheme.bodyMedium?.copyWith(
                                  color: _currentHeadingIndex == index
                                      ? _theme.colorScheme.primary
                                      : _theme.colorScheme.onSurface,
                                  fontWeight: _currentHeadingIndex == index
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          );
                        },
                      ),
                    );
                  }
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildReadingProgressIndicator() {
    return Positioned(
      left: 0,
      top: 0,
      bottom: 0,
      child: Container(
        width: 4,
        decoration: BoxDecoration(
          color: _theme.colorScheme.surfaceVariant,
          borderRadius: BorderRadius.circular(2),
        ),
        child: FractionallySizedBox(
          heightFactor: _scrollProgress,
          alignment: Alignment.topCenter,
          child: Container(
            decoration: BoxDecoration(
              color: _theme.colorScheme.primary,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: _theme.colorScheme.primaryContainer.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Text(
              '技术文章',
              style: _theme.textTheme.labelMedium?.copyWith(
                color: _theme.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: _theme.colorScheme.primary.withOpacity(0.15),
                      blurRadius: 10,
                      offset: const Offset(0, 3),
                      spreadRadius: 1,
                    ),
                  ],
                ),
                child: Icon(
                  Icons.article_rounded,
                  size: 36,
                  color: _theme.colorScheme.primary,
                ),
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: _theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        height: 1.3,
                        letterSpacing: -0.3,
                      ),
                    ),
                    if (_lastUpdated != null || _authorName.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Wrap(
                          spacing: 16,
                          runSpacing: 8,
                          children: [
                            if (_authorName.isNotEmpty)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: _theme.colorScheme.primaryContainer.withOpacity(0.4),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.person_outline,
                                      size: 16,
                                      color: _theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    _authorName,
                                    style: _theme.textTheme.bodyMedium?.copyWith(
                                      color: _theme.colorScheme.onSurface.withOpacity(0.8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            if (_lastUpdated != null)
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: _theme.colorScheme.primaryContainer.withOpacity(0.4),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(
                                      Icons.update,
                                      size: 16,
                                      color: _theme.colorScheme.primary,
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    '更新于 ${_formatDate(_lastUpdated!)}',
                                    style: _theme.textTheme.bodyMedium?.copyWith(
                                      color: _theme.colorScheme.onSurface.withOpacity(0.8),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          if (_headings.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 24),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _theme.colorScheme.secondaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: _theme.colorScheme.outline.withOpacity(0.2),
                  width: 1,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.bookmark,
                        size: 18,
                        color: _theme.colorScheme.secondary,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        "文章概览",
                        style: _theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: _theme.colorScheme.secondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.list),
                        label: const Text('查看目录'),
                        onPressed: () {
                          setState(() {
                            _showTableOfContents = true;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        icon: const Icon(Icons.code),
                        label: const Text('查看源码'),
                        onPressed: () {
                          final url = 'https://github.com/${widget.owner}/${widget.repo}/blob/main/${widget.path}';
                          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
                        },
                        style: TextButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Container(
            margin: const EdgeInsets.only(top: 24, bottom: 8),
            height: 3,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  _theme.colorScheme.primary.withOpacity(0.7),
                  _theme.colorScheme.tertiary.withOpacity(0.2),
                ],
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              ),
              borderRadius: BorderRadius.circular(1.5),
            ),
          ),
        ],
      ),
    );
  }

  Future<String> _getFinalImageUrl(String uri) async {
    String imageUrl = uri.toString();
    String targetPath = '';

    if (imageUrl.startsWith('../') || imageUrl.startsWith('./') || imageUrl.startsWith('@')) {
      String relativePath = imageUrl;
      if (imageUrl.startsWith('../')) {
        relativePath = imageUrl.substring(3);
      } else if (imageUrl.startsWith('./')) {
        relativePath = imageUrl.substring(2);
      }

      final String basePath = widget.path.contains('/')
          ? widget.path.substring(0, widget.path.lastIndexOf('/'))
          : '';

      if (imageUrl.startsWith('../')) {
        if (basePath.contains('/')) {
          targetPath = '${basePath.substring(0, basePath.lastIndexOf('/'))}/$relativePath';
        } else {
          targetPath = relativePath;
        }
      } else {
        targetPath = basePath.isEmpty ? relativePath : '$basePath/$relativePath';
      }
    } else if (imageUrl.contains('github.com') && imageUrl.contains('/blob/')) {
      imageUrl = imageUrl.replaceAll('/blob/', '/raw/');
    }
    return await UnifiedArticleService.getImageContent(targetPath);
  }

  Widget _buildArticleContent() {
    // 创建 Markdown 样式表
    final MarkdownStyleSheet styleSheet = MarkdownStyleSheet(
      // 标题样式
      h1: _theme.textTheme.headlineLarge?.copyWith(
        fontWeight: FontWeight.w800,
        letterSpacing: -0.5,
        height: 1.3,
        color: _theme.colorScheme.onSurface,
        fontSize: 32,
      ),
      h1Padding: const EdgeInsets.only(top: 40, bottom: 20),
      
      h2: _theme.textTheme.headlineMedium?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: -0.5,
        height: 1.3,
        color: _theme.colorScheme.onSurface,
        fontSize: 26,
      ),
      h2Padding: const EdgeInsets.only(top: 32, bottom: 16),
      
      h3: _theme.textTheme.headlineSmall?.copyWith(
        fontWeight: FontWeight.w600,
        letterSpacing: -0.3,
        height: 1.3,
        color: _theme.colorScheme.onSurface,
        fontSize: 22,
      ),
      h3Padding: const EdgeInsets.only(top: 28, bottom: 14),
      
      h4: _theme.textTheme.titleLarge?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: _theme.colorScheme.onSurface,
        fontSize: 19,
      ),
      h4Padding: const EdgeInsets.only(top: 24, bottom: 12),
      
      h5: _theme.textTheme.titleMedium?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: _theme.colorScheme.onSurface,
        fontSize: 17,
      ),
      h5Padding: const EdgeInsets.only(top: 22, bottom: 11),
      
      h6: _theme.textTheme.titleSmall?.copyWith(
        fontWeight: FontWeight.w600,
        height: 1.3,
        color: _theme.colorScheme.onSurface.withOpacity(0.9),
        fontSize: 16,
      ),
      h6Padding: const EdgeInsets.only(top: 20, bottom: 10),
      
      // 段落样式
      p: _theme.textTheme.bodyLarge?.copyWith(
        height: 1.8,
        fontSize: 17,
        letterSpacing: 0.3,
        color: _theme.colorScheme.onSurface.withOpacity(0.9),
        wordSpacing: 0.8,
      ),
      pPadding: const EdgeInsets.only(bottom: 20),
      
      // 强调样式
      em: TextStyle(
        fontStyle: FontStyle.italic,
        color: _theme.colorScheme.onSurface.withOpacity(0.9),
      ),
      
      // 加粗样式
      strong: TextStyle(
        fontWeight: FontWeight.w700,
        color: _theme.colorScheme.onSurface,
        letterSpacing: 0.3,
      ),
      
      // 引用样式
      blockquote: _theme.textTheme.bodyLarge?.copyWith(
        height: 1.7,
        fontSize: 16.5,
        letterSpacing: 0.2,
        color: _theme.colorScheme.onSurface.withOpacity(0.8),
        fontStyle: FontStyle.italic,
      ),
      blockquotePadding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
      blockquoteDecoration: BoxDecoration(
        color: _theme.colorScheme.secondaryContainer.withOpacity(0.3),
        border: Border(
          left: BorderSide(
            color: _theme.colorScheme.secondary.withOpacity(0.5),
            width: 4,
          ),
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      
      // 列表样式
      listBullet: _theme.textTheme.bodyLarge?.copyWith(
        height: 1.8,
        fontSize: 17,
        color: _theme.colorScheme.primary,
      ),
      listBulletPadding: const EdgeInsets.only(right: 10),
      listIndent: 28,
      
      // 代码样式
      code: _theme.textTheme.bodyMedium?.copyWith(
        fontFamily: 'monospace',
        fontSize: 15,
        color: Color(0xFF00BFA5), // 使用与内联代码构建器匹配的颜色
        backgroundColor: _theme.colorScheme.surfaceVariant.withOpacity(0.5),
        letterSpacing: 0.2,
        height: 1.2,
        fontWeight: FontWeight.w500,
        decorationStyle: TextDecorationStyle.solid,
        wordSpacing: 0, // 减小代码中的字间距
        overflow: TextOverflow.visible, // 确保文本不被截断
      ),
      codeblockDecoration: BoxDecoration(
        color: _theme.colorScheme.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _theme.colorScheme.outline.withOpacity(0.1),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: _theme.colorScheme.shadow.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      codeblockPadding: const EdgeInsets.all(16),
      
      // 表格样式
      tableHead: TextStyle(
        fontWeight: FontWeight.bold,
        color: _theme.colorScheme.onSurface,
      ),
      tableBorder: TableBorder.all(
        color: _theme.colorScheme.outline.withOpacity(0.3),
        width: 1,
        borderRadius: BorderRadius.circular(4),
      ),
      tableColumnWidth: const FlexColumnWidth(),
      tableCellsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      
      // 水平线样式
      horizontalRuleDecoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            width: 1,
            color: _theme.colorScheme.outline.withOpacity(0.3),
          ),
        ),
      ),
      
      // 链接样式
      a: TextStyle(
        color: _theme.colorScheme.primary,
        fontWeight: FontWeight.w500,
        decoration: TextDecoration.underline,
        decorationColor: _theme.colorScheme.primary.withOpacity(0.3),
      ),
    );

    return Padding(
      padding: const EdgeInsets.only(top: 20), // 为内容添加顶部间距
      child: MarkdownBody(
        data: _content!,
        selectable: true,
        shrinkWrap: true,
        softLineBreak: true, // 确保长行自动换行
        fitContent: true, // 内容适应宽度
        styleSheet: styleSheet,
        onTapLink: (text, href, title) {
          if (href != null) {
            try {
              launchUrl(Uri.parse(href), mode: LaunchMode.externalApplication);
            } catch (e) {
              dev.log('无法打开链接: $href', name: 'GitHubArticlePage', error: e);
            }
          }
        },
        extensionSet: md.ExtensionSet(
          md.ExtensionSet.gitHubFlavored.blockSyntaxes,
          [
            ...md.ExtensionSet.gitHubFlavored.inlineSyntaxes,
          ],
        ),
        builders: {
          'pre': CodeBlockBuilder(_theme),
          'code': InlineCodeBuilder(_theme),
          'blockquote': QuoteBuilder(_theme),
          'table': CustomTableBuilder(_theme),
          'checkbox': CheckboxBuilder(_theme),
        },
        imageBuilder: (uri, title, alt) {
          return Builder(
            builder: (context) {
              // return FutureBuilder<String>(
              //   future: _getFinalImageUrl(uri.toString()),
              //   builder: (context, snapshot) {
              //     if (snapshot.connectionState != ConnectionState.done) {
              //       return CircularProgressIndicator();
              //     }
              //     if (snapshot.hasError) {
              //       return Icon(Icons.error);
              //     }
              //     return CachedNetworkImage(
              //       imageUrl: snapshot.data!,
              //       placeholder: (context, url) => CircularProgressIndicator(),
              //       errorWidget: (context, url, error) => Icon(Icons.broken_image),
              //     );
              //   },
              // );
              return FutureBuilder<String>(
                future: _getFinalImageUrl(uri.toString()),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return CircularProgressIndicator();
                  }
                  if (snapshot.hasError) {
                    return Icon(Icons.error);
                  }

                  String imageUrl = snapshot.data!;
                  return Container(
                    margin: const EdgeInsets.symmetric(vertical: 20),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 16,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GestureDetector(
                            onTap: () {
                              // 添加点击查看大图的功能
                              showDialog(
                                context: context,
                                builder: (context) => Dialog(
                                  backgroundColor: Colors.transparent,
                                  elevation: 0,
                                  insetPadding: const EdgeInsets.all(16),
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      InteractiveViewer(
                                        clipBehavior: Clip.none,
                                        minScale: 0.5,
                                        maxScale: 4.0,
                                        child: FadeInImage.assetNetwork(
                                          placeholder: 'assets/placeholder.png',
                                          placeholderErrorBuilder: (context, error, stackTrace) {
                                            // Fallback when placeholder image is missing
                                            return Center(
                                              child: CircularProgressIndicator(
                                                valueColor: AlwaysStoppedAnimation<Color>(
                                                  _theme.colorScheme.primary,
                                                ),
                                              ),
                                            );
                                          },
                                          imageErrorBuilder: (context, error, stackTrace) {
                                            dev.log('全屏图片加载错误', name: 'GitHubArticlePage', error: error);
                                            return Container(
                                              padding: const EdgeInsets.all(16),
                                              decoration: BoxDecoration(
                                                color: _theme.colorScheme.errorContainer,
                                                borderRadius: BorderRadius.circular(8),
                                              ),
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    Icons.broken_image_outlined,
                                                    color: _theme.colorScheme.onErrorContainer,
                                                    size: 48,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  Text(
                                                    '图片加载失败',
                                                    style: TextStyle(
                                                      color: _theme.colorScheme.onErrorContainer,
                                                      fontWeight: FontWeight.bold,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 8),
                                                  Text(
                                                    '您也可以尝试点击链接直接访问:\n$imageUrl',
                                                    style: TextStyle(
                                                      color: _theme.colorScheme.onErrorContainer,
                                                      fontSize: 12,
                                                    ),
                                                    textAlign: TextAlign.center,
                                                  ),
                                                  const SizedBox(height: 16),
                                                  ElevatedButton.icon(
                                                    icon: const Icon(Icons.open_in_browser, size: 16),
                                                    label: const Text('在浏览器中打开'),
                                                    onPressed: () {
                                                      launchUrl(Uri.parse(imageUrl),
                                                          mode: LaunchMode.externalApplication);
                                                    },
                                                  ),
                                                ],
                                              ),
                                            );
                                          },
                                          image: imageUrl,
                                          fit: BoxFit.contain,
                                          fadeInDuration: const Duration(milliseconds: 300),
                                          fadeOutDuration: const Duration(milliseconds: 100),
                                        ),
                                      ),
                                      Positioned(
                                        top: 0,
                                        right: 0,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.6),
                                            shape: BoxShape.circle,
                                          ),
                                          child: IconButton(
                                            icon: const Icon(Icons.close),
                                            color: Colors.white,
                                            onPressed: () => Navigator.of(context).pop(),
                                          ),
                                        ),
                                      ),
                                      Positioned(
                                        bottom: 16,
                                        right: 16,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: Colors.black.withOpacity(0.6),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: IconButton(
                                            icon: const Icon(Icons.open_in_browser),
                                            tooltip: '在浏览器中打开',
                                            color: Colors.white,
                                            onPressed: () {
                                              launchUrl(Uri.parse(imageUrl),
                                                  mode: LaunchMode.externalApplication);
                                            },
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            child: Stack(
                              children: [
                                Container(
                                  width: double.infinity,
                                  constraints: const BoxConstraints(
                                    minHeight: 100,
                                    maxHeight: 300,
                                  ),
                                  color: _theme.colorScheme.surfaceVariant.withOpacity(0.3),
                                  child: Center(
                                    child: FadeInImage.assetNetwork(
                                      placeholder: 'assets/placeholder.png',
                                      imageErrorBuilder: (context, error, stackTrace) {
                                        dev.log('图片缩略图加载错误', name: 'GitHubArticlePage', error: error);
                                        return Container(
                                          padding: const EdgeInsets.all(16),
                                          width: double.infinity,
                                          color: _theme.colorScheme.errorContainer.withOpacity(0.5),
                                          child: Column(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.broken_image_outlined,
                                                color: _theme.colorScheme.onErrorContainer,
                                                size: 48,
                                              ),
                                              const SizedBox(height: 16),
                                              Text(
                                                '图片加载失败',
                                                style: TextStyle(
                                                  color: _theme.colorScheme.onErrorContainer,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 8),
                                              Text(
                                                '您可以点击尝试直接访问原始图片',
                                                style: TextStyle(
                                                  color: _theme.colorScheme.onErrorContainer,
                                                  fontSize: 12,
                                                ),
                                                textAlign: TextAlign.center,
                                              ),
                                              const SizedBox(height: 16),
                                              Wrap(
                                                alignment: WrapAlignment.center,
                                                spacing: 8,
                                                children: [
                                                  ElevatedButton.icon(
                                                    icon: const Icon(Icons.refresh, size: 16),
                                                    label: const Text('重试'),
                                                    onPressed: () {
                                                      // 强制重新加载
                                                      setState(() {});
                                                    },
                                                  ),
                                                  OutlinedButton.icon(
                                                    icon: const Icon(Icons.open_in_browser, size: 16),
                                                    label: const Text('在浏览器中打开'),
                                                    onPressed: () {
                                                      launchUrl(Uri.parse(imageUrl),
                                                          mode: LaunchMode.externalApplication);
                                                    },
                                                  ),
                                                ],
                                              ),
                                            ],
                                          ),
                                        );
                                      },
                                      image: imageUrl,
                                      fit: BoxFit.contain,
                                      fadeInDuration: const Duration(milliseconds: 300),
                                      fadeOutDuration: const Duration(milliseconds: 100),
                                    ),
                                  ),
                                ),
                                Positioned(
                                  top: 8,
                                  right: 8,
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: _theme.colorScheme.surface.withOpacity(0.7),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: IconButton(
                                      icon: const Icon(Icons.open_in_full, size: 16),
                                      tooltip: '查看大图',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () {
                                        showDialog(
                                          context: context,
                                          builder: (context) => Dialog(
                                            backgroundColor: Colors.transparent,
                                            elevation: 0,
                                            insetPadding: const EdgeInsets.all(16),
                                            child: Stack(
                                              alignment: Alignment.center,
                                              children: [
                                                InteractiveViewer(
                                                  clipBehavior: Clip.none,
                                                  minScale: 0.5,
                                                  maxScale: 4.0,
                                                  child: FadeInImage.assetNetwork(
                                                    placeholder: 'assets/placeholder.png',
                                                    placeholderErrorBuilder: (context, error, stackTrace) {
                                                      // Fallback when placeholder image is missing
                                                      return Center(
                                                        child: CircularProgressIndicator(
                                                          valueColor: AlwaysStoppedAnimation<Color>(
                                                            _theme.colorScheme.primary,
                                                          ),
                                                        ),
                                                      );
                                                    },
                                                    imageErrorBuilder: (context, error, stackTrace) {
                                                      dev.log('全屏图片加载错误', name: 'GitHubArticlePage', error: error);
                                                      return Container(
                                                        padding: const EdgeInsets.all(16),
                                                        decoration: BoxDecoration(
                                                          color: _theme.colorScheme.errorContainer,
                                                          borderRadius: BorderRadius.circular(8),
                                                        ),
                                                        child: Column(
                                                          mainAxisSize: MainAxisSize.min,
                                                          children: [
                                                            Icon(
                                                              Icons.broken_image_outlined,
                                                              color: _theme.colorScheme.onErrorContainer,
                                                              size: 48,
                                                            ),
                                                            const SizedBox(height: 16),
                                                            Text(
                                                              '图片加载失败',
                                                              style: TextStyle(
                                                                color: _theme.colorScheme.onErrorContainer,
                                                                fontWeight: FontWeight.bold,
                                                              ),
                                                            ),
                                                            const SizedBox(height: 8),
                                                            Text(
                                                              '您也可以尝试点击链接直接访问:\n$imageUrl',
                                                              style: TextStyle(
                                                                color: _theme.colorScheme.onErrorContainer,
                                                                fontSize: 12,
                                                              ),
                                                              textAlign: TextAlign.center,
                                                            ),
                                                            const SizedBox(height: 16),
                                                            ElevatedButton.icon(
                                                              icon: const Icon(Icons.open_in_browser, size: 16),
                                                              label: const Text('在浏览器中打开'),
                                                              onPressed: () {
                                                                launchUrl(Uri.parse(imageUrl),
                                                                    mode: LaunchMode.externalApplication);
                                                              },
                                                            ),
                                                          ],
                                                        ),
                                                      );
                                                    },
                                                    image: imageUrl,
                                                    fit: BoxFit.contain,
                                                    fadeInDuration: const Duration(milliseconds: 300),
                                                    fadeOutDuration: const Duration(milliseconds: 100),
                                                  ),
                                                ),
                                                Positioned(
                                                  top: 0,
                                                  right: 0,
                                                  child: Container(
                                                    decoration: BoxDecoration(
                                                      color: Colors.black.withOpacity(0.6),
                                                      shape: BoxShape.circle,
                                                    ),
                                                    child: IconButton(
                                                      icon: const Icon(Icons.close),
                                                      color: Colors.white,
                                                      onPressed: () => Navigator.of(context).pop(),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          if (alt != null && alt.isNotEmpty)
                            Container(
                              width: double.infinity,
                              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                              decoration: BoxDecoration(
                                color: _theme.colorScheme.surfaceVariant.withOpacity(0.3),
                                borderRadius: const BorderRadius.only(
                                  bottomLeft: Radius.circular(12),
                                  bottomRight: Radius.circular(12),
                                ),
                              ),
                              child: Text(
                                alt,
                                textAlign: TextAlign.center,
                                style: _theme.textTheme.bodyMedium?.copyWith(
                                  color: _theme.colorScheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              );

            }
          );
        },
      ),
    );
  }

  String _getRandomLoadingTip() {
    final tips = [
      '从 GitHub 获取最新内容...',
      '正在解析 Markdown 格式...',
      '准备精彩内容，请稍候...',
      '正在优化阅读体验...',
      '马上就好，感谢您的耐心等待...',
    ];
    return tips[Random().nextInt(tips.length)];
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);
    
    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        if (difference.inMinutes == 0) {
          return '刚刚';
        }
        return '${difference.inMinutes}分钟前';
      }
      return '${difference.inHours}小时前';
    } else if (difference.inDays < 30) {
      return '${difference.inDays}天前';
    } else {
      final formatter = DateFormat('yyyy年MM月dd日');
      return formatter.format(date);
    }
  }

  Widget _buildContent() {
    if (_isLoading) {
      return _buildLoadingState();
    }

    if (_error != null) {
      return _buildErrorState();
    }

    if (_content == null || _content!.isEmpty) {
      return Center(
        child: Text(
          '没有内容',
          style: _theme.textTheme.titleLarge,
        ),
      );
    }

    return Stack(
      children: [
        Card(
          elevation: 6, // 增加立体感
          shadowColor: Colors.black.withOpacity(0.2),
          margin: EdgeInsets.zero,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          _theme.colorScheme.surface,
                          _theme.colorScheme.surface.withOpacity(0.97),
                        ],
                        stops: const [0.0, 1.0],
                      ),
                    ),
                  ),
                ),
                // 完全移除分离的标题部分，将所有内容放入滚动区域
                LayoutBuilder(
                  builder: (context, constraints) {
                    return Stack(
                      children: [
                        // 滚动内容区域
                        Builder(
                          builder: (context) {
                            return Scrollbar(
                              controller: _scrollController,
                              thumbVisibility: true,
                              thickness: 8,
                              radius: const Radius.circular(4),
                              child: ScrollConfiguration(
                                behavior: ScrollConfiguration.of(context).copyWith(
                                  scrollbars: true,
                                  overscroll: true,
                                  physics: const BouncingScrollPhysics(),
                                ),
                                child: SingleChildScrollView(
                                  controller: _scrollController,
                                  padding: const EdgeInsets.fromLTRB(32, 32, 32, 48),
                                  child: ConstrainedBox(
                                    constraints: BoxConstraints(
                                      minWidth: constraints.maxWidth - 64, // 减去左右内边距
                                      maxWidth: constraints.maxWidth - 64, // 限制最大宽度
                                    ),
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        // 将标题部分移动到这里，使其随内容一起滚动
                                        _buildHeader(),
                                        // 内容部分
                                        _buildArticleContent(),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          }
                        ),
                        // 阅读进度指示器
                        _buildReadingProgressIndicator(),
                      ],
                    );
                  }
                ),
              ],
            ),
          ),
        ),
        Positioned(
          bottom: 0,
          left: 0,
          right: 0,
          height: 40,
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  _theme.colorScheme.surface.withOpacity(0.0),
                  _theme.colorScheme.surface.withOpacity(0.1),
                ],
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          bottom: 28,
          right: 28,
          curve: Curves.easeInOut,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 200),
            opacity: _scrollProgress > 0.1 ? 1.0 : 0.0,
            child: FloatingActionButton.small(
              onPressed: () {
                if (_scrollController.hasClients) {
                  _scrollController.animateTo(
                    0,
                    duration: const Duration(milliseconds: 500),
                    curve: Curves.easeInOut,
                  );
                }
              },
              tooltip: '返回顶部',
              elevation: 4,
              child: const Icon(Icons.arrow_upward),
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    _theme = Theme.of(context);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    
    // 在小屏幕上调整布局
    final isSmallScreen = screenWidth < 768;
    
    return PageContainer(
      padding: const EdgeInsets.symmetric(horizontal: 8.0, vertical: 16.0),
      child: LayoutBuilder(
        builder: (context, constraints) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // 目录侧边栏
              _buildTableOfContents(),
              // 文章主体
              Flexible(
                child: Center(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxWidth: isSmallScreen ? screenWidth - 16 : 960, // 在小屏幕上允许更宽的内容
                      maxHeight: screenHeight - 80,
                    ),
                    child: _buildContent(),
                  ),
                ),
              ),
            ],
          );
        }
      ),
    );
  }
}

class _HeadingInfo {
  final String text;
  final int level;
  final double position;
  
  _HeadingInfo({
    required this.text,
    required this.level,
    required this.position,
  });
}

class _HeadingBuilder extends MarkdownElementBuilder {
  final int index;
  final AutoScrollController controller;
  final List<_HeadingInfo> headings;
  
  _HeadingBuilder(this.index, this.controller, this.headings);
  
  @override
  Widget? visitText(md.Text text, TextStyle? preferredStyle) {
    return null; // 返回null以使用默认实现
  }
  
  @override
  Widget build(BuildContext context, List<Widget> children) {
    final headingIndex = headings.indexWhere(
      (heading) => heading.level == index + 1 && children.isNotEmpty && 
                 children[0] is RichText && 
                 (children[0] as RichText).text.toPlainText() == heading.text
    );
    
    if (headingIndex != -1) {
      return AutoScrollTag(
        key: ValueKey('heading-$headingIndex'),
        controller: controller,
        index: headingIndex,
        child: Padding(
          padding: const EdgeInsets.only(top: 24, bottom: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: children,
                    ),
                  ),
                ],
              ),
              if (index <= 1) // 只为h1和h2添加分隔线
                const Padding(
                  padding: EdgeInsets.only(top: 8),
                  child: Divider(),
                ),
            ],
          ),
        ),
      );
    }
    
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: children,
    );
  }
}

class CodeBlockBuilder extends MarkdownElementBuilder {
  final ThemeData theme;
  
  CodeBlockBuilder(this.theme);

  @override
  void visitElementBefore(md.Element element) {
    super.visitElementBefore(element);

    dev.log(
      'element.attributes ${element.attributes}',
      name: 'GitHubArticlePage',
    );
  }
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    String language = '';
    String code = element.textContent;
    
    // 提取语言标识
    if (element.attributes.containsKey('class')) {
      String className = element.attributes['class'] as String;
      if (className.startsWith('language-')) {
        language = className.substring(9);
      }
    }

    // 语法高亮实现
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 代码语言标识和复制按钮
          if (language.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceVariant.withOpacity(0.9),
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outline.withOpacity(0.1),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: theme.colorScheme.primary.withOpacity(0.2),
                        width: 1,
                      ),
                    ),
                    child: Text(
                      language.toUpperCase(),
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      return IconButton(
                        icon: const Icon(Icons.copy, size: 16),
                        tooltip: '复制代码',
                        visualDensity: VisualDensity.compact,
                        onPressed: () {
                          Clipboard.setData(ClipboardData(text: code));
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.check_circle_outline, 
                                    color: theme.colorScheme.onInverseSurface,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  const Text('代码已复制'),
                                ],
                              ),
                              behavior: SnackBarBehavior.floating,
                              backgroundColor: theme.colorScheme.inverseSurface,
                              width: 150,
                              duration: const Duration(seconds: 1),
                            ),
                          );
                        },
                      );
                    }
                  ),
                ],
              ),
            ),
          // 代码内容区域改进
          Container(
            constraints: const BoxConstraints(
              minHeight: 50,
            ),
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(0, 16, 16, 16),
            color: theme.colorScheme.surface.withOpacity(0.8),
            child: Builder(
              builder: (context) {
                // Create a dedicated ScrollController for this code block
                final codeScrollController = ScrollController();
                
                return Scrollbar(
                  controller: codeScrollController,
                  thumbVisibility: true,
                  thickness: 6,
                  radius: const Radius.circular(3),
                  child: SingleChildScrollView(
                    controller: codeScrollController,
                    scrollDirection: Axis.horizontal,
                    child: _buildHighlightedCode(code, language),
                  ),
                );
              }
            ),
          ),
        ],
      ),
    );
  }
  
  // 简单的语法高亮实现
  Widget _buildHighlightedCode(String code, String language) {
    // 语法高亮的基本样式
    final baseStyle = theme.textTheme.bodyMedium?.copyWith(
      fontFamily: 'monospace',
      height: 1.6,
      fontSize: 14.5,
      color: theme.colorScheme.onSurface,
      letterSpacing: 0.2,
    );
    
    // 各种语法元素的样式 - 使用更鲜明的配色方案
    final keywordStyle = baseStyle?.copyWith(
      color: Color(0xFF7C4DFF), // 深紫色关键字
      fontWeight: FontWeight.bold,
    );
    
    final commentStyle = baseStyle?.copyWith(
      color: theme.colorScheme.onSurface.withOpacity(0.5),
      fontStyle: FontStyle.italic,
    );
    
    final stringStyle = baseStyle?.copyWith(
      color: Color(0xFF00BFA5), // 青绿色字符串
    );
    
    final numberStyle = baseStyle?.copyWith(
      color: Color(0xFFFF6D00), // 橙色数字
    );
    
    final punctuationStyle = baseStyle?.copyWith(
      color: theme.colorScheme.onSurface.withOpacity(0.7),
      fontWeight: FontWeight.w500,
    );
    
    final classStyle = baseStyle?.copyWith(
      color: Color(0xFF1565C0), // 蓝色类名
      fontWeight: FontWeight.w600,
    );
    
    final functionStyle = baseStyle?.copyWith(
      color: Color(0xFFFF8F00), // 琥珀色函数名
    );
    
    // 关键字列表 (根据语言可以自定义)
    final keywords = <String>[];
    final classDefs = <String>[];
    final functions = <String>[];
    
    switch (language.toLowerCase()) {
      case 'dart':
        keywords.addAll([
          'class', 'interface', 'void', 'int', 'double', 'String', 'bool', 'true', 'false',
          'final', 'const', 'var', 'late', 'static', 'this', 'super', 'new', 'null',
          'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break', 'continue',
          'return', 'try', 'catch', 'finally', 'throw', 'assert', 'private', 'public',
          'protected', 'import', 'export', 'package', 'extends', 'implements',
          'async', 'await', 'Future', 'Stream', 'List', 'Map', 'Set', 'dynamic',
          'override', 'get', 'set', 'required', 'abstract', 'sealed', 'enum', 'mixin',
        ]);
        classDefs.addAll([
          'Widget', 'State', 'StatefulWidget', 'StatelessWidget', 'BuildContext',
          'Container', 'Row', 'Column', 'Stack', 'Padding', 'Scaffold', 'AppBar',
          'Text', 'Icon', 'Image', 'MaterialApp', 'Theme', 'Color',
        ]);
        functions.addAll([
          'build', 'initState', 'dispose', 'setState', 'print', 'map', 'where', 'forEach',
        ]);
        break;
      case 'java':
      case 'kotlin':
        keywords.addAll([
          'class', 'interface', 'void', 'int', 'double', 'String', 'boolean', 'true', 'false',
          'final', 'const', 'var', 'val', 'static', 'this', 'super', 'new', 'null',
          'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'break', 'continue',
          'return', 'try', 'catch', 'finally', 'throw', 'throws', 'private', 'public',
          'protected', 'import', 'package', 'extends', 'implements',
          'synchronized', 'volatile', 'instanceof', 'enum',
        ]);
        break;
      case 'javascript':
      case 'js':
      case 'typescript':
      case 'ts':
        keywords.addAll([
          'var', 'let', 'const', 'function', 'class', 'interface', 'extends',
          'implements', 'type', 'enum', 'return', 'if', 'else', 'for', 'while',
          'do', 'switch', 'case', 'break', 'continue', 'default', 'try', 'catch',
          'finally', 'throw', 'this', 'super', 'new', 'import', 'export', 'from',
          'as', 'async', 'await', 'true', 'false', 'null', 'undefined',
        ]);
        classDefs.addAll(['Object', 'Array', 'Promise', 'Map', 'Set', 'Date', 'Error']);
        functions.addAll(['console.log', 'setTimeout', 'fetch', 'map', 'filter', 'reduce']);
        break;
      case 'python':
        keywords.addAll([
          'def', 'class', 'if', 'else', 'elif', 'for', 'while', 'in', 'not', 'and', 'or',
          'try', 'except', 'finally', 'raise', 'return', 'import', 'from', 'as',
          'global', 'nonlocal', 'lambda', 'pass', 'break', 'continue', 'True', 'False',
          'None', 'with', 'assert', 'yield', 'del', 'is',
        ]);
        break;
      case 'html':
        keywords.addAll([
          '<html>', '</html>', '<head>', '</head>', '<body>', '</body>',
          '<div>', '</div>', '<span>', '</span>', '<p>', '</p>',
          '<h1>', '</h1>', '<h2>', '</h2>', '<h3>', '</h3>',
          '<a>', '</a>', '<img>', '<br>', '<input>', '<form>', '</form>',
          '<table>', '</table>', '<tr>', '</tr>', '<td>', '</td>',
          '<script>', '</script>', '<style>', '</style>',
        ]);
        break;
      case 'css':
        keywords.addAll([
          'body', 'div', 'span', 'p', 'h1', 'h2', 'h3', 'a', 'img',
          'margin', 'padding', 'border', 'color', 'background', 'display',
          'position', 'width', 'height', 'flex', 'grid', 'font', 'text-align',
          '@media', '@import', '@keyframes', 'animation', 'transition',
        ]);
        break;
      default:
        // 默认关键字
        keywords.addAll([
          'if', 'else', 'for', 'while', 'return', 'function', 'class', 'var',
          'let', 'const', 'int', 'float', 'double', 'string', 'bool', 'true', 'false',
        ]);
    }
    
    // 分割代码为行
    final lines = code.split('\n');
    
    // 生成富文本
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < lines.length; i++)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 行号
                Container(
                  width: 40,
                  padding: const EdgeInsets.only(right: 10),
                  alignment: Alignment.centerRight,
                  decoration: BoxDecoration(
                    border: Border(
                      right: BorderSide(
                        color: theme.colorScheme.outline.withOpacity(0.1),
                        width: 1,
                      ),
                    ),
                    color: theme.colorScheme.surfaceVariant.withOpacity(0.3),
                  ),
                  child: Text(
                    '${i + 1}',
                    style: baseStyle?.copyWith(
                      color: theme.colorScheme.onSurface.withOpacity(0.5),
                      fontSize: 12,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                // 代码行内容
                _highlightLine(lines[i], baseStyle!, keywordStyle!, commentStyle!, 
                               stringStyle!, numberStyle!, punctuationStyle!, 
                               classStyle!, functionStyle!, keywords, classDefs, functions),
              ],
            ),
          ),
      ],
    );
  }
  
  // 高亮单行代码
  Widget _highlightLine(String line, TextStyle baseStyle, TextStyle keywordStyle, 
                         TextStyle commentStyle, TextStyle stringStyle, 
                         TextStyle numberStyle, TextStyle punctuationStyle,
                         TextStyle classStyle, TextStyle functionStyle,
                         List<String> keywords, List<String> classDefs, List<String> functions) {
    final spans = <TextSpan>[];
    
    // 整行注释检测
    if (line.trim().startsWith('//') || line.trim().startsWith('#') || line.trim().startsWith('<!--')) {
      spans.add(TextSpan(text: line, style: commentStyle));
      return RichText(text: TextSpan(children: spans));
    }
    
    // 分词 - 使用更精确的分词规则
    final pattern = r'[a-zA-Z][a-zA-Z0-9_]*|".*?"|' + r"'.*?'|\d+(\.\d+)?|//.*|[^\w\s]|\s+";
    final matches = RegExp(pattern, multiLine: true).allMatches(line).toList();
    
    // 行内注释检测
    int commentStartIndex = -1;
    for (int i = 0; i < matches.length; i++) {
      final match = matches[i];
      final word = match.group(0) ?? '';
      if (word == '/' && i + 1 < matches.length && matches[i + 1].group(0) == '/') {
        commentStartIndex = i;
        break;
      } else if (word.startsWith('//')) {
        commentStartIndex = i;
        break;
      }
    }
    
    for (int i = 0; i < matches.length; i++) {
      // 如果已经进入注释部分
      if (commentStartIndex != -1 && i >= commentStartIndex) {
        final commentText = line.substring(matches[commentStartIndex].start);
        spans.add(TextSpan(text: commentText, style: commentStyle));
        break;
      }
      
      final match = matches[i];
      final word = match.group(0) ?? '';
      
      // 字符串
      if ((word.startsWith('"') && word.endsWith('"')) || 
          (word.startsWith("'") && word.endsWith("'"))) {
        spans.add(TextSpan(text: word, style: stringStyle));
      }
      // 数字
      else if (RegExp(r'^\d+(\.\d+)?$').hasMatch(word)) {
        spans.add(TextSpan(text: word, style: numberStyle));
      }
      // 关键字
      else if (keywords.contains(word)) {
        spans.add(TextSpan(text: word, style: keywordStyle));
      }
      // 类名
      else if (classDefs.contains(word) || 
              (RegExp(r'^[A-Z][a-zA-Z0-9_]*$').hasMatch(word) && word.length > 1)) {
        spans.add(TextSpan(text: word, style: classStyle));
      }
      // 函数
      else if (functions.contains(word) || 
              (i + 1 < matches.length && matches[i + 1].group(0) == '(')) {
        spans.add(TextSpan(text: word, style: functionStyle));
      }
      // 标点符号和其他
      else {
        spans.add(TextSpan(text: word, style: baseStyle));
      }
    }
    
    return RichText(text: TextSpan(children: spans));
  }
}

// 自定义引用块构建器
class QuoteBuilder extends MarkdownElementBuilder {
  final ThemeData theme;
  
  QuoteBuilder(this.theme);
  
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    // 解析引用内容
    final content = element.textContent;
    
    // 检测是否有特殊标记 (警告、信息、提示等)
    bool isWarning = content.toLowerCase().contains('警告') || 
                    content.toLowerCase().contains('warning') ||
                    content.toLowerCase().contains('caution') ||
                    content.toLowerCase().contains('注意');
                    
    bool isInfo = content.toLowerCase().contains('信息') || 
                  content.toLowerCase().contains('info') ||
                  content.toLowerCase().contains('information') ||
                  content.toLowerCase().contains('说明');
                  
    bool isTip = content.toLowerCase().contains('提示') || 
                 content.toLowerCase().contains('tip') ||
                 content.toLowerCase().contains('hint') ||
                 content.toLowerCase().contains('小贴士');
    
    // 设置样式
    Color borderColor;
    Color backgroundColor;
    IconData iconData;
    
    if (isWarning) {
      borderColor = theme.colorScheme.error.withOpacity(0.6);
      backgroundColor = theme.colorScheme.errorContainer.withOpacity(0.2);
      iconData = Icons.warning_amber_rounded;
    } else if (isInfo) {
      borderColor = theme.colorScheme.primary.withOpacity(0.6);
      backgroundColor = theme.colorScheme.primaryContainer.withOpacity(0.2);
      iconData = Icons.info_outline;
    } else if (isTip) {
      borderColor = theme.colorScheme.tertiary.withOpacity(0.6);
      backgroundColor = theme.colorScheme.tertiaryContainer.withOpacity(0.2);
      iconData = Icons.lightbulb_outline;
    } else {
      borderColor = theme.colorScheme.secondary.withOpacity(0.5);
      backgroundColor = theme.colorScheme.secondaryContainer.withOpacity(0.2);
      iconData = Icons.format_quote;
    }
    
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(8),
        border: Border(
          left: BorderSide(
            color: borderColor,
            width: 4,
          ),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            iconData,
            color: borderColor,
            size: 20,
          ),
          const SizedBox(width: 12),
          Flexible(
            fit: FlexFit.tight,
            child: MarkdownBody(
              data: content,
              selectable: true,
              shrinkWrap: true,
              styleSheet: MarkdownStyleSheet(
                p: theme.textTheme.bodyLarge?.copyWith(
                  height: 1.6,
                  color: theme.colorScheme.onSurface.withOpacity(0.9),
                  fontStyle: FontStyle.italic,
                ),
                a: TextStyle(
                  color: theme.colorScheme.primary,
                  fontWeight: FontWeight.w500,
                  decoration: TextDecoration.underline,
                  decorationColor: theme.colorScheme.primary.withOpacity(0.3),
                ),
                strong: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface,
                ),
                em: TextStyle(
                  fontStyle: FontStyle.italic,
                  color: theme.colorScheme.onSurface.withOpacity(0.85),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 自定义表格构建器
class CustomTableBuilder extends MarkdownElementBuilder {
  final ThemeData theme;

  CustomTableBuilder(this.theme);

  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final rows = element.children ?? [];
    if (rows.isEmpty) return const SizedBox.shrink();

    // 计算最大列数，确保所有行有相同数量的单元格
    int maxColumns = 0;
    for (final row in rows) {
      if (row is md.Element) {
        final cellCount = row.children?.length ?? 0;
        if (cellCount > maxColumns) maxColumns = cellCount;
      }
    }
    if (maxColumns == 0) return const SizedBox.shrink();

    final tableRows = <TableRow>[];
    final hasHeader = rows.length > 1;

    // 处理表头
    if (hasHeader && rows.first is md.Element) {
      final headerCells = (rows.first as md.Element).children ?? [];
      tableRows.add(_buildTableRow(headerCells, maxColumns, isHeader: true, rowIndex: 0));
    }

    // 处理表格主体
    final bodyRows = hasHeader ? rows.sublist(1) : rows;
    for (int i = 0; i < bodyRows.length; i++) {
      final row = bodyRows[i];
      if (row is md.Element) {
        final cells = row.children ?? [];
        tableRows.add(_buildTableRow(cells, maxColumns, isHeader: false, rowIndex: i));
      }
    }

    if (tableRows.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.3),
          width: 1,
        ),
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withOpacity(0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Scrollbar(
        thumbVisibility: true,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Table(
            defaultColumnWidth: const FixedColumnWidth(200), // 适当减小宽度
            border: TableBorder(
              horizontalInside: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.2),
                width: 1,
              ),
              verticalInside: BorderSide(
                color: theme.colorScheme.outline.withOpacity(0.2),
                width: 1,
              ),
            ),
            children: tableRows,
          ),
        ),
      ),
    );
  }

  TableRow _buildTableRow(List<md.Node> cells, int maxColumns, {required bool isHeader, required int rowIndex}) {
    final List<Widget> cellWidgets = [];

    // 添加现有单元格
    for (final cell in cells) {
      cellWidgets.add(_buildCell(cell, isHeader: isHeader));
    }

    // 填充缺少的单元格以确保行长度一致
    while (cellWidgets.length < maxColumns) {
      cellWidgets.add(_buildEmptyCell(isHeader: isHeader));
    }

    return TableRow(
      decoration: BoxDecoration(
        color: isHeader
            ? theme.colorScheme.primaryContainer.withOpacity(0.3)
            : (rowIndex % 2 == 0
                ? Colors.transparent
                : theme.colorScheme.surfaceVariant.withOpacity(0.3)),
      ),
      children: cellWidgets,
    );
  }

  Widget _buildCell(md.Node cell, {required bool isHeader}) {
    String text = '';
    if (cell is md.Element) {
      text = cell.textContent;
    } else {
      text = cell.textContent;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Text(
        text,
        style: theme.textTheme.bodyMedium?.copyWith(
          fontWeight: isHeader ? FontWeight.w600 : FontWeight.normal,
          color: isHeader
              ? theme.colorScheme.onPrimaryContainer
              : theme.colorScheme.onSurface,
        ),
      ),
    );
  }

  Widget _buildEmptyCell({required bool isHeader}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: const Text(''),
    );
  }
}

// 自定义任务列表复选框构建器
class CheckboxBuilder extends MarkdownElementBuilder {
  final ThemeData theme;
  
  CheckboxBuilder(this.theme);
  
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final text = element.textContent;
    // 检查是否包含 [x] 或 [ ] 模式
    final isChecked = text.trim().startsWith('[x]') || text.trim().startsWith('[X]');
    
    // 提取任务描述文本
    final taskText = text.replaceFirst(RegExp(r'\[[ xX]\]'), '').trim();
    
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min, // 避免Row无限扩展
        children: [
          SizedBox(
            width: 24,
            height: 24,
            child: Checkbox(
              value: isChecked,
              onChanged: null, // 只读复选框
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(4),
              ),
              side: BorderSide(
                color: theme.colorScheme.primary.withOpacity(0.5),
                width: 1.5,
              ),
            ),
          ),
          const SizedBox(width: 8),
          Flexible(
            fit: FlexFit.tight,
            child: Text(
              taskText,
              style: theme.textTheme.bodyMedium?.copyWith(
                height: 1.5,
                decoration: isChecked ? TextDecoration.lineThrough : null,
                color: isChecked 
                    ? theme.colorScheme.onSurface.withOpacity(0.6)
                    : theme.colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// 自定义内联代码构建器
class InlineCodeBuilder extends MarkdownElementBuilder {
  final ThemeData theme;
  
  InlineCodeBuilder(this.theme);
  
  @override
  Widget visitElementAfter(md.Element element, TextStyle? preferredStyle) {
    final String code = element.textContent;
    
    // 应用简单的代码语法高亮
    final spans = _highlightInlineCode(code);
    
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 2),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceVariant.withOpacity(0.6),
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: theme.colorScheme.outline.withOpacity(0.2),
          width: 1,
        ),
      ),
      child: IntrinsicWidth(
        child: RichText(
          text: TextSpan(
            children: spans,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'monospace',
              fontSize: 14.5,
              color: Color(0xFF00BFA5), // 默认颜色为字符串色
              letterSpacing: 0.2,
              height: 1.2,
              fontWeight: FontWeight.w500,
            ),
          ),
          overflow: TextOverflow.visible,
          softWrap: true, // 允许自动换行
        ),
      ),
    );
  }
  
  // 简单的内联代码高亮
  List<TextSpan> _highlightInlineCode(String code) {
    final spans = <TextSpan>[];
    
    // 高亮样式
    final keywordStyle = TextStyle(
      color: Color(0xFF7C4DFF), // 深紫色关键字
      fontWeight: FontWeight.bold,
    );
    
    final numberStyle = TextStyle(
      color: Color(0xFFFF6D00), // 橙色数字
    );
    
    final stringStyle = TextStyle(
      color: Color(0xFF00BFA5), // 青绿色字符串
    );
    
    final classStyle = TextStyle(
      color: Color(0xFF1565C0), // 蓝色类名
      fontWeight: FontWeight.w600,
    );
    
    // 关键字列表 - 扩展关键字列表以支持更多常见编程语言
    final keywords = [
      // 控制流关键字
      'if', 'else', 'for', 'while', 'do', 'switch', 'case', 'default',
      'break', 'continue', 'return', 'yield', 'await', 'async',
      
      // 声明关键字
      'function', 'class', 'interface', 'enum', 'struct', 'var', 'let', 'const',
      'final', 'static', 'void', 'public', 'private', 'protected',
      
      // 类型关键字
      'int', 'float', 'double', 'boolean', 'bool', 'string', 'String', 'char',
      'Object', 'Array', 'Map', 'Set', 'List', 'Future', 'Stream',
      
      // 操作符和值关键字
      'new', 'this', 'super', 'true', 'false', 'null', 'undefined', 'nil', 'None',
      'in', 'is', 'as', 'typeof', 'instanceof', 'extends', 'implements',
      
      // 异常处理
      'try', 'catch', 'finally', 'throw', 'throws',
    ];
    
    try {
      // 简单的代码分割模式 - 修复转义单引号的问题
      final pattern = r'[a-zA-Z][a-zA-Z0-9_]*|".*?"|' + r"'.*?'" + r'|\d+(\.\d+)?|[^\w\s]+|\s+';
      final matches = RegExp(pattern, multiLine: true).allMatches(code).toList();
      
      for (final match in matches) {
        final word = match.group(0) ?? '';
        
        // 字符串
        if ((word.startsWith('"') && word.endsWith('"')) || 
            (word.startsWith("'") && word.endsWith("'"))) {
          spans.add(TextSpan(text: word, style: stringStyle));
        }
        // 数字
        else if (RegExp(r'^\d+(\.\d+)?$').hasMatch(word)) {
          spans.add(TextSpan(text: word, style: numberStyle));
        }
        // 关键字
        else if (keywords.contains(word)) {
          spans.add(TextSpan(text: word, style: keywordStyle));
        }
        // 类名 (大写字母开头)
        else if (RegExp(r'^[A-Z][a-zA-Z0-9_]*$').hasMatch(word) && word.length > 1) {
          spans.add(TextSpan(text: word, style: classStyle));
        }
        // 其他
        else {
          spans.add(TextSpan(text: word));
        }
      }
    } catch (e) {
      // 如果正则表达式处理出错，简单返回原始文本
      spans.add(TextSpan(text: code));
    }
    
    // 如果没有匹配项，返回原始文本
    if (spans.isEmpty) {
      spans.add(TextSpan(text: code));
    }
    
    return spans;
  }
}