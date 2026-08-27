// lib/app/router/app_router.dart
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../core/widgets/diabla_bottom_nav.dart';
import '../../features/addresses/presentation/screens/addresses_screen.dart';
import '../../features/admin/presentation/screens/admin_dashboard_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/splash_screen.dart';
import '../../features/cart/presentation/screens/cart_screen.dart';
import '../../features/checkout/presentation/screens/checkout_screen.dart';
import '../../features/driver/presentation/screens/driver_dashboard_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/menu/presentation/screens/menu_screen.dart';
import '../../features/menu/presentation/screens/product_detail_screen.dart';
import '../../features/notifications/presentation/screens/notifications_screen.dart';
import '../../features/orders/presentation/screens/order_detail_screen.dart';
import '../../features/orders/presentation/screens/orders_screen.dart';
import '../../features/profile/presentation/screens/profile_screen.dart';
import '../../features/qr/presentation/screens/qr_screen.dart';
import '../../features/tracking/presentation/screens/order_tracking_screen.dart';
import '../../features/wallet/presentation/screens/wallet_screen.dart';
import 'route_names.dart';

final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

final GoRouter appRouter = GoRouter(
  navigatorKey: rootNavigatorKey,
  initialLocation: '/splash',
  routes: [
    GoRoute(
      path: '/splash',
      name: RouteNames.splash,
      builder: (context, state) => const SplashScreen(),
    ),
    GoRoute(
      path: '/auth',
      name: RouteNames.auth,
      builder: (context, state) => const LoginScreen(),
    ),

    // Stateful ShellRoute con BottomNavigationBar permanente
    StatefulShellRoute.indexedStack(
      builder: (context, state, navigationShell) {
        return Scaffold(
          body: navigationShell,
          bottomNavigationBar: DiablaBottomNav(navigationShell: navigationShell),
        );
      },
      branches: [
        // Rama 0: Home
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/home',
              name: RouteNames.home,
              builder: (context, state) => const HomeScreen(),
            ),
          ],
        ),

        // Rama 1: Menu
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/menu',
              name: RouteNames.menu,
              builder: (context, state) => const MenuScreen(),
              routes: [
                GoRoute(
                  path: ':categoryId',
                  builder: (context, state) {
                    final categoryId = state.pathParameters['categoryId'];
                    return MenuScreen(categoryId: categoryId);
                  },
                ),
              ],
            ),
          ],
        ),

        // Rama 2: Cart
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/cart',
              name: RouteNames.cart,
              builder: (context, state) => const CartScreen(),
            ),
          ],
        ),

        // Rama 3: Orders
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/orders',
              name: RouteNames.orders,
              builder: (context, state) => const OrdersScreen(),
            ),
          ],
        ),

        // Rama 4: Profile
        StatefulShellBranch(
          routes: [
            GoRoute(
              path: '/profile',
              name: RouteNames.profile,
              builder: (context, state) => const ProfileScreen(),
            ),
          ],
        ),
      ],
    ),

    // Rutas fuera del Shell (pantallas completas)
    GoRoute(
      path: '/product/:productId',
      name: RouteNames.productDetail,
      builder: (context, state) {
        final productId = state.pathParameters['productId']!;
        return ProductDetailScreen(productId: productId);
      },
    ),
    GoRoute(
      path: '/checkout',
      name: RouteNames.checkout,
      builder: (context, state) => const CheckoutScreen(),
    ),
    GoRoute(
      path: '/addresses',
      name: RouteNames.addresses,
      builder: (context, state) => const AddressesScreen(),
    ),
    GoRoute(
      path: '/orders/:orderId',
      name: RouteNames.orderDetail,
      builder: (context, state) {
        final orderId = state.pathParameters['orderId']!;
        return OrderDetailScreen(orderId: orderId);
      },
    ),
    GoRoute(
      path: '/tracking/:orderId',
      name: RouteNames.tracking,
      builder: (context, state) {
        final orderId = state.pathParameters['orderId']!;
        return OrderTrackingScreen(orderId: orderId);
      },
    ),
    GoRoute(
      path: '/notifications',
      name: RouteNames.notifications,
      builder: (context, state) => const NotificationsScreen(),
    ),
    GoRoute(
      path: '/wallet',
      name: 'wallet',
      builder: (context, state) => const WalletScreen(),
    ),
    GoRoute(
      path: '/qr',
      name: RouteNames.qr,
      builder: (context, state) => const QrScreen(),
    ),
    GoRoute(
      path: '/driver',
      name: 'driver',
      builder: (context, state) => const DriverDashboardScreen(),
    ),
    GoRoute(
      path: '/admin',
      name: 'admin',
      builder: (context, state) => const AdminDashboardScreen(),
    ),
  ],
);
