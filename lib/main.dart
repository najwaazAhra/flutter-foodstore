import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const FoodStoreApp());
}

class ApiConfig {
  // Android Emulator: 10.0.2.2 | Flutter Web/Desktop: localhost
  // Untuk HP fisik, ganti dengan IP laptop/PC yang satu jaringan Wi-Fi.
  static const baseUrl =
    'http://localhost/food-store/public/api/';

  static const storageUrl =
    'http://localhost/food-store/public/storage/';
}

class FoodApi {
  FoodApi() {
    dio = Dio(BaseOptions(
      baseUrl: ApiConfig.baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 20),
      headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
    ));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (options, handler) async {
      final token = await storage.read(key: 'token');
      if (token != null && token.isNotEmpty) {
        options.headers['Authorization'] = 'Bearer $token';
      }
      handler.next(options);
    }, onError: (error, handler) async {
      if (error.response?.statusCode == 401) await storage.delete(key: 'token');
      handler.next(error);
    }));
  }

  late final Dio dio;
  static const storage = FlutterSecureStorage();

  dynamic _data(dynamic response) => response is Map ? (response['data'] ?? response) : response;
  List<Map<String, dynamic>> _list(dynamic response) {
    dynamic value = _data(response);
    if (value is Map) value = value['data'] ?? value['products'] ?? value['categories'] ?? value['sliders'] ?? value['carts'] ?? value['orders'] ?? [];
    if (value is! List) return [];
    return value.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final r = await dio.post('customer/login', data: {'email': email, 'password': password});
    final body = Map<String, dynamic>.from(r.data);
    final token = body['token']?.toString();
    if (token != null) await storage.write(key: 'token', value: token);
    return body;
  }
  Future<String> register(String name, String email, String password, String confirm) async {
    final r = await dio.post('customer/register', data: {'name': name, 'email': email, 'password': password, 'password_confirmation': confirm});
    return (r.data is Map ? r.data['message'] : null)?.toString() ?? 'Registrasi berhasil';
  }
  Future<void> logout() async {
    try { await dio.post('customer/logout'); } finally { await storage.delete(key: 'token'); }
  }
  Future<List<Map<String, dynamic>>> products({String query = ''}) async => _list((await dio.get('public/products', queryParameters: query.isEmpty ? null : {'search': query})).data);
  Future<List<Map<String, dynamic>>> popularProducts() async => _list((await dio.get('public/products-popular')).data);
  Future<List<Map<String, dynamic>>> categories() async => _list((await dio.get('public/categories')).data);
  Future<List<Map<String, dynamic>>> sliders() async => _list((await dio.get('public/sliders')).data);
  Future<List<Map<String, dynamic>>> carts() async => _list((await dio.get('public/carts')).data);
  Future<void> addCart(dynamic productId) async => dio.post('public/carts', data: {'product_id': productId});
  Future<void> increment(dynamic id) async => dio.post('public/carts/increment', data: {'id': id});
  Future<void> decrement(dynamic id) async => dio.post('public/carts/decrement', data: {'id': id});
  Future<void> removeCart(dynamic id) async => dio.delete('public/carts/$id');
  Future<List<Map<String, dynamic>>> orders() async => _list((await dio.get('customer/my-orders')).data);
  Future<Map<String, dynamic>> profile() async {
    final r = await dio.get('customer/profile');
    final d = _data(r.data);
    if (d is Map && d['customer'] is Map) return Map<String, dynamic>.from(d['customer']);
    return d is Map ? Map<String, dynamic>.from(d) : {};
  }
}

class FoodStoreApp extends StatefulWidget {
  const FoodStoreApp({super.key});
  @override
  State<FoodStoreApp> createState() => _FoodStoreAppState();
}
class _FoodStoreAppState extends State<FoodStoreApp> {
  final api = FoodApi();
  bool loggedIn = false;
  bool checking = true;
  @override
  void initState() { super.initState(); _checkLogin(); }
  Future<void> _checkLogin() async {
    final token = await FoodApi.storage.read(key: 'token');
    if (mounted) setState(() { loggedIn = token != null; checking = false; });
  }
  void onLogin() => setState(() => loggedIn = true);
  Future<void> onLogout() async { await api.logout(); if (mounted) setState(() => loggedIn = false); }
  @override
  Widget build(BuildContext context) => MaterialApp(
    debugShowCheckedModeBanner: false,
    title: 'Food Store',
    theme: ThemeData(useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFFFF7A1A)), scaffoldBackgroundColor: const Color(0xFFFFF8F0), fontFamily: 'Roboto'),
    home: checking ? const Scaffold(body: Center(child: CircularProgressIndicator())) : loggedIn
      ? StoreShell(api: api, onLogout: onLogout)
      : AuthPage(api: api, onLogin: onLogin),
  );
}

const orange = Color(0xFFFF7A1A);
const cream = Color(0xFFFFF8F0);
String textOf(dynamic value, [String fallback = '']) => value == null ? fallback : value.toString();
dynamic firstOf(Map<String, dynamic> m, List<String> keys) { for (final k in keys) { if (m[k] != null) return m[k]; } return null; }
String money(dynamic value) { final n = num.tryParse(textOf(value, '0')) ?? 0; return 'Rp ${n.toStringAsFixed(0)}'; }
String imageUrl(dynamic value) { final s = textOf(value); if (s.isEmpty) return ''; if (s.startsWith('http')) return s; return '${ApiConfig.storageUrl}$s'; }

class AuthPage extends StatefulWidget {
  final FoodApi api; final VoidCallback onLogin;
  const AuthPage({super.key, required this.api, required this.onLogin});
  @override State<AuthPage> createState() => _AuthPageState();
}
class _AuthPageState extends State<AuthPage> {
  final email = TextEditingController(), password = TextEditingController(), name = TextEditingController(), confirm = TextEditingController();
  bool registerMode = false, busy = false, obscure = true;
  String error = '';
  @override void dispose() { email.dispose(); password.dispose(); name.dispose(); confirm.dispose(); super.dispose(); }
  Future<void> submit() async {
    if (email.text.trim().isEmpty || password.text.isEmpty || (registerMode && name.text.trim().isEmpty)) { setState(() => error = 'Lengkapi semua kolom terlebih dahulu.'); return; }
    if (registerMode && password.text != confirm.text) { setState(() => error = 'Konfirmasi password tidak sama.'); return; }
    setState(() { busy = true; error = ''; });
    try {
      if (registerMode) {
        final msg = await widget.api.register(name.text.trim(), email.text.trim(), password.text, confirm.text);
        if (mounted) setState(() { registerMode = false; error = '$msg. Silakan login.'; });
      } else {
        await widget.api.login(email.text.trim(), password.text);
        widget.onLogin();
      }
    } on DioException catch (e) {
      final d = e.response?.data;
      setState(() => error = d is Map ? textOf(d['message'], 'Periksa email dan password.') : 'Tidak dapat terhubung ke server. Periksa alamat API dan server Laravel.');
    } catch (e) { setState(() => error = 'Terjadi kesalahan: $e'); }
    if (mounted) setState(() => busy = false);
  }
  @override Widget build(BuildContext context) => Scaffold(body: Center(child: SingleChildScrollView(padding: const EdgeInsets.all(24), child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 430), child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
    Container(height: 92, width: 92, alignment: Alignment.center, decoration: BoxDecoration(color: orange, borderRadius: BorderRadius.circular(28)), child: const Icon(Icons.restaurant_menu, color: Colors.white, size: 48)),
    const SizedBox(height: 24), Text(registerMode ? 'Buat Akun' : 'Selamat Datang!', style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold)),
    const SizedBox(height: 6), Text(registerMode ? 'Daftar untuk mulai memesan makanan.' : 'Masuk ke akun Food Store kamu.', style: const TextStyle(color: Colors.black54)), const SizedBox(height: 28),
    if (registerMode) _field(name, 'Nama lengkap', Icons.person_outline), _field(email, 'Email', Icons.email_outlined, type: TextInputType.emailAddress),
    TextField(controller: password, obscureText: obscure, decoration: InputDecoration(labelText: 'Password', prefixIcon: const Icon(Icons.lock_outline), suffixIcon: IconButton(onPressed: () => setState(() => obscure = !obscure), icon: Icon(obscure ? Icons.visibility : Icons.visibility_off)), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))),
    if (registerMode) ...[const SizedBox(height: 14), _field(confirm, 'Konfirmasi password', Icons.lock_outline, obscure: true)],
    if (error.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 12), child: Text(error, style: TextStyle(color: error.contains('berhasil') || error.contains('Silakan') ? Colors.green : Colors.red))),
    const SizedBox(height: 20), FilledButton(style: FilledButton.styleFrom(backgroundColor: orange, padding: const EdgeInsets.symmetric(vertical: 16)), onPressed: busy ? null : submit, child: busy ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : Text(registerMode ? 'Daftar' : 'Login')),
    TextButton(onPressed: busy ? null : () => setState(() { registerMode = !registerMode; error = ''; }), child: Text(registerMode ? 'Sudah punya akun? Login' : 'Belum punya akun? Daftar')),
  ])))));
  Widget _field(TextEditingController c, String label, IconData icon, {TextInputType type = TextInputType.text, bool obscure = false}) => Padding(padding: const EdgeInsets.only(bottom: 14), child: TextField(controller: c, keyboardType: type, obscureText: obscure, decoration: InputDecoration(labelText: label, prefixIcon: Icon(icon), border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)))));
}

class StoreShell extends StatefulWidget {
  final FoodApi api; final Future<void> Function() onLogout;
  const StoreShell({super.key, required this.api, required this.onLogout});
  @override State<StoreShell> createState() => _StoreShellState();
}
class _StoreShellState extends State<StoreShell> {
  int index = 0;
  @override Widget build(BuildContext context) {
    final pages = [HomeTab(api: widget.api, onGo: (i) => setState(() => index = i)), OrdersTab(api: widget.api), CartTab(api: widget.api), ProfileTab(api: widget.api, onLogout: widget.onLogout)];
    return Scaffold(appBar: AppBar(backgroundColor: cream, title: const Text('Food Store', style: TextStyle(fontWeight: FontWeight.bold)), actions: [IconButton(icon: const Icon(Icons.search), onPressed: () async { final q = await showSearch<String?>(context: context, delegate: ProductSearch(widget.api)); if (q != null && mounted) Navigator.of(context).push(MaterialPageRoute(builder: (_) => SearchResults(api: widget.api, query: q))); })]), body: IndexedStack(index: index, children: pages), bottomNavigationBar: NavigationBar(selectedIndex: index, onDestinationSelected: (v) => setState(() => index = v), destinations: const [NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'), NavigationDestination(icon: Icon(Icons.receipt_long_outlined), selectedIcon: Icon(Icons.receipt_long), label: 'Pesanan'), NavigationDestination(icon: Icon(Icons.shopping_cart_outlined), selectedIcon: Icon(Icons.shopping_cart), label: 'Keranjang'), NavigationDestination(icon: Icon(Icons.person_outline), selectedIcon: Icon(Icons.person), label: 'Profil') ]));
  }
}

class HomeTab extends StatefulWidget {
  final FoodApi api; final ValueChanged<int> onGo;
  const HomeTab({super.key, required this.api, required this.onGo});
  @override State<HomeTab> createState() => _HomeTabState();
}
class _HomeTabState extends State<HomeTab> {
  late Future<List<dynamic>> all;
  @override void initState() { super.initState(); all = Future.wait([widget.api.sliders(), widget.api.categories(), widget.api.popularProducts(), widget.api.products()]); }
  Future<void> reload() async { setState(() => all = Future.wait([widget.api.sliders(), widget.api.categories(), widget.api.popularProducts(), widget.api.products()])); }
  @override Widget build(BuildContext context) => RefreshIndicator(onRefresh: reload, child: FutureBuilder<List<dynamic>>(future: all, builder: (context, snap) {
    if (snap.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator());
    if (snap.hasError) return _error(snap.error.toString());
    final sliders = snap.data![0] as List<Map<String,dynamic>>, categories = snap.data![1] as List<Map<String,dynamic>>, popular = snap.data![2] as List<Map<String,dynamic>>, products = snap.data![3] as List<Map<String,dynamic>>;
    return ListView(padding: const EdgeInsets.fromLTRB(16, 8, 16, 24), children: [
      Container(padding: const EdgeInsets.all(20), decoration: BoxDecoration(gradient: const LinearGradient(colors: [Color(0xFFFFA34D), orange]), borderRadius: BorderRadius.circular(22)), child: const Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('Lapar? Yuk makan!', style: TextStyle(color: Colors.white, fontSize: 23, fontWeight: FontWeight.bold)), SizedBox(height: 6), Text('Temukan makanan favoritmu hari ini.', style: TextStyle(color: Colors.white))])),
      if (sliders.isNotEmpty) ...[const SizedBox(height: 18), SizedBox(height: 150, child: PageView.builder(itemCount: sliders.length, itemBuilder: (_, i) => _networkImage(firstOf(sliders[i], ['image','photo']), radius: 18)))],
      _sectionTitle('Kategori', 'Lihat pilihan makanan'),
      if (categories.isEmpty) const Text('Belum ada kategori.') else SizedBox(height: 104, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: categories.length, separatorBuilder: (_,__) => const SizedBox(width: 12), itemBuilder: (_,i) { final c = categories[i]; return SizedBox(width: 84, child: Column(children: [_networkImage(firstOf(c,['image','icon']), radius: 18, height: 64, width: 64), const SizedBox(height: 6), Text(textOf(c['name'],'Kategori'), maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12))])); })) ,
      _sectionTitle('Produk Populer', 'Paling banyak disukai'),
      if (popular.isEmpty) const Text('Belum ada produk populer.') else SizedBox(height: 225, child: ListView.separated(scrollDirection: Axis.horizontal, itemCount: popular.length, separatorBuilder: (_,__) => const SizedBox(width: 12), itemBuilder: (_,i) => SizedBox(width: 160, child: ProductTile(api: widget.api, product: popular[i])))),
      _sectionTitle('Produk Terbaru', 'Pilihan makanan lainnya'),
      if (products.isEmpty) const Text('Belum ada produk.') else GridView.builder(shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: products.length, gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount: 2, childAspectRatio: .72, crossAxisSpacing: 12, mainAxisSpacing: 12), itemBuilder: (_,i) => ProductTile(api: widget.api, product: products[i])),
    ]);
  }));
  Widget _error(String e) => ListView(children: [const SizedBox(height: 100), const Icon(Icons.cloud_off, size: 48), const Center(child: Text('Gagal memuat data dari Laravel.')), Padding(padding: const EdgeInsets.all(16), child: Text(e, textAlign: TextAlign.center)), Center(child: FilledButton(onPressed: reload, child: const Text('Coba lagi')))]);
}

Widget _sectionTitle(String title, String subtitle) => Padding(padding: const EdgeInsets.only(top: 22, bottom: 12), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)), Text(subtitle, style: const TextStyle(color: Colors.black54, fontSize: 12))]), const Icon(Icons.chevron_right, color: orange)]));

Widget _networkImage(
  dynamic path, {
  double height = 110,
  double width = double.infinity,
  double radius = 14,
}) {
  final url = imageUrl(path);

  debugPrint('IMAGE PATH: $path');
  debugPrint('IMAGE URL: $url');

  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: url.isEmpty
        ? Container(
            height: height,
            width: width,
            color: const Color(0xFFFFE3CB),
            child: const Icon(Icons.restaurant, color: orange),
          )
        : Image.network(
            url,
            height: height,
            width: width,
            fit: BoxFit.cover,
            errorBuilder: (_, error, stackTrace) {
              debugPrint('IMAGE ERROR: $error');

              return Container(
                height: height,
                width: width,
                color: const Color(0xFFFFE3CB),
                child: const Icon(
                  Icons.image_not_supported,
                  color: orange,
                ),
              );
            },
          ),
  );
}
class ProductTile extends StatelessWidget {
  final FoodApi api; final Map<String,dynamic> product;
  const ProductTile({super.key, required this.api, required this.product});
  @override Widget build(BuildContext context) {
    final id = firstOf(product,['id','product_id']); final name = textOf(product['name'],'Produk'); final price = firstOf(product,['price','selling_price','harga']); final photo = firstOf(product,['image','photo','thumbnail']);
    return InkWell(onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ProductDetail(api: api, product: product))), child: Container(padding: const EdgeInsets.all(9), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(17), boxShadow: [BoxShadow(color: Colors.black.withOpacity(.04), blurRadius: 10)]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Expanded(child: _networkImage(photo, radius: 13)), const SizedBox(height: 8), Text(name, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)), const SizedBox(height: 4), Text(money(price), style: const TextStyle(color: orange, fontWeight: FontWeight.bold)), const SizedBox(height: 5), SizedBox(width: double.infinity, child: FilledButton.tonal(onPressed: id == null ? null : () async { try { await api.addCart(id); if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Produk ditambahkan ke keranjang'))); } catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal menambahkan produk. Login ulang jika sesi berakhir.'))); } }, child: const Text('Tambah', style: TextStyle(fontSize: 12))))])));
  }
}

class ProductDetail extends StatelessWidget {
  final FoodApi api; final Map<String,dynamic> product;
  const ProductDetail({super.key, required this.api, required this.product});
  @override Widget build(BuildContext context) { final id = firstOf(product,['id','product_id']); return Scaffold(appBar: AppBar(title: const Text('Detail Produk')), body: ListView(padding: const EdgeInsets.all(18), children: [_networkImage(firstOf(product,['image','photo']), height: 250, radius: 20), const SizedBox(height: 18), Text(textOf(product['name'],'Produk'), style: const TextStyle(fontSize: 24,fontWeight: FontWeight.bold)), const SizedBox(height: 8), Text(money(firstOf(product,['price','selling_price','harga'])), style: const TextStyle(fontSize: 20,color: orange,fontWeight: FontWeight.bold)), const SizedBox(height: 18), const Text('Deskripsi', style: TextStyle(fontWeight: FontWeight.bold)), const SizedBox(height: 6), Text(textOf(firstOf(product,['description','deskripsi']),'Tidak ada deskripsi.')), const SizedBox(height: 24), FilledButton(onPressed: id == null ? null : () async { try { await api.addCart(id); if (context.mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ditambahkan ke keranjang'))); Navigator.pop(context); } } catch (_) { if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tidak dapat menambahkan produk.'))); } }, child: const Text('Tambah ke Keranjang'))])); }
}

class CartTab extends StatefulWidget { final FoodApi api; const CartTab({super.key, required this.api}); @override State<CartTab> createState() => _CartTabState(); }
class _CartTabState extends State<CartTab> {
  late Future<List<Map<String,dynamic>>> future;
  @override void initState() { super.initState(); future = widget.api.carts(); }
  void refresh() => setState(() => future = widget.api.carts());
  Future<void> action(Future<void> Function() fn) async { try { await fn(); refresh(); } catch (e) { if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Aksi gagal: $e'))); } }
  @override Widget build(BuildContext context) => FutureBuilder(future: future, builder: (context,s) { if (s.connectionState != ConnectionState.done) return const Center(child: CircularProgressIndicator()); if (s.hasError) return Center(child: Text('Gagal memuat keranjang: ${s.error}')); final rows = s.data ?? []; if (rows.isEmpty) return const Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.shopping_cart_outlined,size:60,color: orange), SizedBox(height:12), Text('Keranjang masih kosong')])); num total = 0; for (final c in rows) { total += (num.tryParse(textOf(firstOf(c,['price','subtotal','total']),'0')) ?? 0); } return Column(children: [Expanded(child: ListView.separated(padding: const EdgeInsets.all(16), itemCount: rows.length, separatorBuilder: (_,__) => const Divider(), itemBuilder: (_,i) { final c=rows[i]; final p = c['product'] is Map ? Map<String,dynamic>.from(c['product']) : c; final id=firstOf(c,['id','cart_id']); final qty=num.tryParse(textOf(firstOf(c,['quantity','qty']),'1'))?.toInt() ?? 1; return ListTile(contentPadding: EdgeInsets.zero, leading: SizedBox(width:65,child:_networkImage(firstOf(p,['image','photo']),height:65,width:65)), title: Text(textOf(p['name'],'Produk')), subtitle: Text(money(firstOf(c,['subtotal','price']) ?? p['price'])), trailing: Row(mainAxisSize: MainAxisSize.min, children: [IconButton(onPressed: id==null?null:()=>action(()=>widget.api.decrement(id)), icon: const Icon(Icons.remove_circle_outline)), Text('$qty'), IconButton(onPressed: id==null?null:()=>action(()=>widget.api.increment(id)), icon: const Icon(Icons.add_circle_outline)), IconButton(onPressed: id==null?null:()=>action(()=>widget.api.removeCart(id)), icon: const Icon(Icons.delete_outline,color: Colors.red))])); })), Container(color: Colors.white,padding: const EdgeInsets.all(18), child: Column(children: [Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [const Text('Total sementara',style:TextStyle(fontWeight:FontWeight.bold)),Text(money(total),style:const TextStyle(fontWeight:FontWeight.bold,color:orange,fontSize:18))]), const SizedBox(height:12), const Text('Untuk melanjutkan checkout, pastikan alamat dan ongkos kirim sudah diatur pada layanan Laravel.'), const SizedBox(height:10), SizedBox(width:double.infinity,child:FilledButton(onPressed: () => ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Checkout membutuhkan data alamat dan ongkir dari backend.'))), child: const Text('Lanjut Checkout')))]))]); });
}

class OrdersTab extends StatefulWidget { final FoodApi api; const OrdersTab({super.key,required this.api}); @override State<OrdersTab> createState()=>_OrdersTabState(); }
class _OrdersTabState extends State<OrdersTab> { late Future<List<Map<String,dynamic>>> future; @override void initState(){super.initState();future=widget.api.orders();} @override Widget build(BuildContext context)=>FutureBuilder(future:future,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.hasError)return Center(child:Text('Gagal memuat pesanan: ${s.error}'));final rows=s.data??[];if(rows.isEmpty)return const Center(child:Text('Belum ada riwayat pesanan.'));return ListView.separated(padding:const EdgeInsets.all(16),itemCount:rows.length,separatorBuilder:(_,__)=>const SizedBox(height:10),itemBuilder:(_,i){final o=rows[i];return Card(child:ListTile(leading:const CircleAvatar(backgroundColor:Color(0xFFFFE3CB),child:Icon(Icons.receipt_long,color:orange)),title:Text(textOf(firstOf(o,['snap_token','invoice','order_code']),'Pesanan')),subtitle:Text(textOf(firstOf(o,['status','transaction_status']),'Status belum tersedia')),trailing:Text(money(firstOf(o,['total_price','grand_total','total'])))));});}); }

class ProfileTab extends StatefulWidget { final FoodApi api; final Future<void> Function() onLogout; const ProfileTab({super.key,required this.api,required this.onLogout}); @override State<ProfileTab> createState()=>_ProfileTabState(); }
class _ProfileTabState extends State<ProfileTab> { late Future<Map<String,dynamic>> future; @override void initState(){super.initState();future=widget.api.profile();} @override Widget build(BuildContext context)=>FutureBuilder(future:future,builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.hasError)return Center(child:Text('Gagal memuat profil: ${s.error}'));final p=s.data??{};return ListView(padding:const EdgeInsets.all(20),children:[const CircleAvatar(radius:42,backgroundColor:Color(0xFFFFE3CB),child:Icon(Icons.person,size:48,color:orange)),const SizedBox(height:14),Center(child:Text(textOf(p['name'],'Pengguna Food Store'),style:const TextStyle(fontSize:21,fontWeight:FontWeight.bold))),Center(child:Text(textOf(p['email']),style:const TextStyle(color:Colors.black54))),const SizedBox(height:24),Card(child:Column(children:[ListTile(leading:const Icon(Icons.person_outline),title:const Text('Nama'),subtitle:Text(textOf(p['name'],'-'))),const Divider(height:1),ListTile(leading:const Icon(Icons.email_outlined),title:const Text('Email'),subtitle:Text(textOf(p['email'],'-')))])),const SizedBox(height:20),OutlinedButton.icon(onPressed:()async{await widget.onLogout();},icon:const Icon(Icons.logout),label:const Text('Logout'),style:OutlinedButton.styleFrom(foregroundColor:Colors.red))]);}); }

class ProductSearch extends SearchDelegate<String?> { final FoodApi api; ProductSearch(this.api); @override List<Widget>? buildActions(BuildContext context)=>[IconButton(onPressed:()=>query='',icon:const Icon(Icons.clear))]; @override Widget? buildLeading(BuildContext context)=>IconButton(onPressed:()=>close(context,null),icon:const Icon(Icons.arrow_back)); @override Widget buildResults(BuildContext context)=>const Center(child:Text('Tekan enter untuk mencari produk')); @override Widget buildSuggestions(BuildContext context)=>ListTile(leading:const Icon(Icons.search),title:Text('Cari "$query"'),onTap:()=>close(context,query)); }
class SearchResults extends StatelessWidget { final FoodApi api; final String query; const SearchResults({super.key,required this.api,required this.query}); @override Widget build(BuildContext context)=>Scaffold(appBar:AppBar(title:Text('Hasil: $query')),body:FutureBuilder(future:api.products(query:query),builder:(context,s){if(s.connectionState!=ConnectionState.done)return const Center(child:CircularProgressIndicator());if(s.hasError)return Center(child:Text('Pencarian gagal: ${s.error}'));final p=s.data??[];if(p.isEmpty)return const Center(child:Text('Produk tidak ditemukan'));return GridView.builder(padding:const EdgeInsets.all(16),itemCount:p.length,gridDelegate:const SliverGridDelegateWithFixedCrossAxisCount(crossAxisCount:2,childAspectRatio:.72,crossAxisSpacing:12,mainAxisSpacing:12),itemBuilder:(_,i)=>ProductTile(api:api,product:p[i]));})); }
