import 'package:flutter/material.dart';
import 'package:responsive_framework/responsive_framework.dart';
import 'package:go_router/go_router.dart';
import '../widgets/blog_card.dart';
import '../widgets/page_container.dart';
import '../services/unified_article_service.dart';
import '../models/unified_article.dart';
import 'dart:developer' as dev;
import 'dart:math' show min;

class HomePage extends StatefulWidget {
  const HomePage({super.key});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  String _selectedCategory = '全部';
  List<String> _categories = ['全部'];
  final ScrollController _scrollController = ScrollController();
  bool _showBackToTop = false;
  bool _isLoadingCategories = true;
  List<UnifiedArticle> _articles = [];
  bool _isLoadingArticles = true;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 1200),
      vsync: this,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, 0.2),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _scrollController.addListener(_onScroll);
    _controller.forward();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final allArticles = await UnifiedArticleService.getAllCategorizedArticles(validateFiles: true);

      if (allArticles.isEmpty) {
        setState(() {
          _isLoadingCategories = false;
          _isLoadingArticles = false;
        });
        return;
      }

      // 提取所有分类
      final categorySet = allArticles
          .where((a) => a.category.isNotEmpty)
          .map((a) => a.category)
          .toSet();

      setState(() {
        _categories = ['全部', ...categorySet];
        _articles = allArticles;
        _isLoadingCategories = false;
        _isLoadingArticles = false;
      });

      // 异步加载前几篇文章的详细信息（用于首页展示）
      _loadArticleDetails();
    } catch (e) {
      dev.log('数据加载失败', name: 'HomePage', error: e);
      if (mounted) {
        setState(() {
          _isLoadingCategories = false;
          _isLoadingArticles = false;
        });
      }
    }
  }

  /// 异步加载文章详细信息（摘要、图片等）
  Future<void> _loadArticleDetails() async {
    // 只加载前4篇文章的详情用于首页展示
    final articlesToLoad = _articles.take(4).toList();

    for (int i = 0; i < articlesToLoad.length; i++) {
      if (!mounted) return;
      try {
        final detailedArticle = await UnifiedArticleService.getArticleDetails(articlesToLoad[i]);
        if (mounted) {
          setState(() {
            _articles[i] = detailedArticle;
          });
        }
      } catch (e) {
        dev.log('获取文章详情失败: ${articlesToLoad[i].title}', name: 'HomePage', error: e);
      }
    }
  }

  /// 获取当前分类的文章
  List<UnifiedArticle> _getFilteredArticles() {
    if (_selectedCategory == '全部') {
      return _articles;
    }
    return _articles
        .where((article) => article.category == _selectedCategory)
        .toList();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    final showBackToTop = _scrollController.offset > 300;
    if (showBackToTop != _showBackToTop) {
      setState(() {
        _showBackToTop = showBackToTop;
      });
    }
  }

  void _scrollToTop() {
    _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() {}),
      onExit: (_) => setState(() {}),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 32),
        padding: const EdgeInsets.all(32),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primaryContainer,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(
              color: Theme.of(context).colorScheme.shadow.withOpacity(0.1),
              blurRadius: 20,
              offset: const Offset(0, 8),
              spreadRadius: 4,
            ),
          ],
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              Theme.of(context).colorScheme.primary.withOpacity(0.1),
              Theme.of(context).colorScheme.primaryContainer,
              Theme.of(context).colorScheme.tertiary.withOpacity(0.1),
            ],
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SlideTransition(
              position: _slideAnimation,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ShaderMask(
                  shaderCallback: (bounds) {
                    return LinearGradient(
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                      colors: [
                        Theme.of(context).colorScheme.primary,
                        Theme.of(context).colorScheme.tertiary,
                      ],
                    ).createShader(bounds);
                  },
                  child: Text(
                    '欢迎来到我的博客',
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                      letterSpacing: -0.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SlideTransition(
              position: Tween<Offset>(
                begin: const Offset(0, 0.2),
                end: Offset.zero,
              ).animate(
                CurvedAnimation(
                  parent: _controller,
                  curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
                ),
              ),
              child: FadeTransition(
                opacity: CurvedAnimation(
                  parent: _controller,
                  curve: const Interval(0.2, 0.8, curve: Curves.easeOutCubic),
                ),
                child: Text(
                  '分享技术见解，记录学习心得',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    color: Theme.of(
                      context,
                    ).colorScheme.onPrimaryContainer.withOpacity(0.8),
                    height: 1.4,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 32),
            Row(
              children: [
                _buildAnimatedButton(
                  icon: Icons.person_outline,
                  label: '关于我',
                  onPressed: () => context.go('/about'),
                  delay: 0.4,
                  isPrimary: true,
                ),
                const SizedBox(width: 16),
                _buildAnimatedButton(
                  icon: Icons.article_outlined,
                  label: '浏览文章',
                  onPressed: () => context.go('/articles'),
                  delay: 0.5,
                  isPrimary: false,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAnimatedButton({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    required double delay,
    required bool isPrimary,
  }) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.2),
        end: Offset.zero,
      ).animate(
        CurvedAnimation(
          parent: _controller,
          curve: Interval(delay, delay + 0.4, curve: Curves.easeOutCubic),
        ),
      ),
      child: FadeTransition(
        opacity: CurvedAnimation(
          parent: _controller,
          curve: Interval(delay, delay + 0.4, curve: Curves.easeOutCubic),
        ),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: TweenAnimationBuilder<double>(
            duration: const Duration(milliseconds: 200),
            tween: Tween<double>(begin: 1.0, end: 1.0),
            builder: (context, scale, child) {
              return Transform.scale(scale: scale, child: child);
            },
            child:
                isPrimary
                    ? FilledButton.icon(
                      onPressed: onPressed,
                      icon: Icon(icon),
                      label: Text(label),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    )
                    : OutlinedButton.icon(
                      onPressed: onPressed,
                      icon: Icon(icon),
                      label: Text(label),
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 16,
                        ),
                      ),
                    ),
          ),
        ),
      ),
    );
  }

  Widget _buildCategories(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 32),
      width: double.infinity,
      child:
          _isLoadingCategories
              ? const Center(child: CircularProgressIndicator())
              : Wrap(
                spacing: 12,
                runSpacing: 12,
                children:
                    _categories.map((category) {
                      return FilterChip(
                        label: Text(category),
                        selected: _selectedCategory == category,
                        onSelected: (_) => setState(() => _selectedCategory = category),
                      );
                    }).toList(),
              ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final isDesktop = ResponsiveBreakpoints.of(context).largerThan(TABLET);
    final crossAxisCount = isDesktop ? 2 : 1;
    final filteredArticles = _getFilteredArticles();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(-0.2, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _controller,
                        curve: const Interval(
                          0.2,
                          0.6,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                    ),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: Text(
                        '最新文章',
                        style: Theme.of(context).textTheme.headlineMedium
                            ?.copyWith(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.2, 0),
                      end: Offset.zero,
                    ).animate(
                      CurvedAnimation(
                        parent: _controller,
                        curve: const Interval(
                          0.3,
                          0.7,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                    ),
                    child: FadeTransition(
                      opacity: _fadeAnimation,
                      child: TextButton.icon(
                        onPressed: () => context.go('/articles'),
                        icon: const Icon(Icons.arrow_forward),
                        label: const Text('查看全部'),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              _buildCategories(context),
              if (_isLoadingArticles)
                const Center(child: CircularProgressIndicator())
              else if (filteredArticles.isEmpty)
                Center(
                  child: Text(
                    '该分类下暂无文章',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                )
              else
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: crossAxisCount,
                    crossAxisSpacing: 16,
                    mainAxisSpacing: 16,
                    mainAxisExtent: 480,
                  ),
                  itemCount: min(2, filteredArticles.length),
                  itemBuilder: (context, index) {
                    final article = filteredArticles[index];
                    return AnimatedBuilder(
                      animation: _controller,
                      builder: (context, child) {
                        final delay = 0.4 + (index * 0.1);
                        final slideAnimation = Tween<Offset>(
                          begin: const Offset(0, 0.2),
                          end: Offset.zero,
                        ).animate(
                          CurvedAnimation(
                            parent: _controller,
                            curve: Interval(
                              delay.clamp(0.0, 1.0),
                              (delay + 0.4).clamp(0.0, 1.0),
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                        );
                        final fadeAnimation = Tween<double>(
                          begin: 0.0,
                          end: 1.0,
                        ).animate(
                          CurvedAnimation(
                            parent: _controller,
                            curve: Interval(
                              delay.clamp(0.0, 1.0),
                              (delay + 0.4).clamp(0.0, 1.0),
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                        );
                        final scaleAnimation = Tween<double>(
                          begin: 0.95,
                          end: 1.0,
                        ).animate(
                          CurvedAnimation(
                            parent: _controller,
                            curve: Interval(
                              delay.clamp(0.0, 1.0),
                              (delay + 0.4).clamp(0.0, 1.0),
                              curve: Curves.easeOutCubic,
                            ),
                          ),
                        );
                        return SlideTransition(
                          position: slideAnimation,
                          child: ScaleTransition(
                            scale: scaleAnimation,
                            child: FadeTransition(
                              opacity: fadeAnimation,
                              child: child,
                            ),
                          ),
                        );
                      },
                      child: BlogCard(key: ValueKey(article.path), post: article),
                    );
                  },
                ),
            ],
          ),
        ),
        if (isDesktop) ...[
          const SizedBox(width: 32),
          SizedBox(
            width: 300,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.2, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: _controller,
                      curve: const Interval(
                        0.3,
                        0.7,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                  ),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: Text(
                      '推荐阅读',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                SlideTransition(
                  position: Tween<Offset>(
                    begin: const Offset(0.2, 0),
                    end: Offset.zero,
                  ).animate(
                    CurvedAnimation(
                      parent: _controller,
                      curve: const Interval(
                        0.4,
                        0.8,
                        curve: Curves.easeOutCubic,
                      ),
                    ),
                  ),
                  child: FadeTransition(
                    opacity: _fadeAnimation,
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: Card(
                        elevation: 1,
                        child: InkWell(
                          onTap: () => context.go('/article/page'),
                          borderRadius: BorderRadius.circular(12),
                          child: Container(
                            padding: const EdgeInsets.all(16),
                            child: Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.all(8),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(
                                          context,
                                        ).colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Icon(
                                    Icons.science,
                                    color:
                                        Theme.of(context).colorScheme.primary,
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        'Gson原理',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        '深入解析 Gson 的工作原理',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall?.copyWith(
                                          color:
                                              Theme.of(
                                                context,
                                              ).colorScheme.onSurfaceVariant,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 16,
                                  color:
                                      Theme.of(
                                        context,
                                      ).colorScheme.onSurfaceVariant,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        PageContainer(
          child: SingleChildScrollView(
            controller: _scrollController,
            physics: const BouncingScrollPhysics(),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [_buildHeader(context), _buildContent(context)],
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeInOut,
          right: 24,
          bottom: _showBackToTop ? 24 : -60,
          child: FloatingActionButton.extended(
            onPressed: _scrollToTop,
            icon: const Icon(Icons.arrow_upward),
            label: const Text('返回顶部'),
          ),
        ),
      ],
    );
  }
}
