# Nexo

Nexo is a modern personal finance app built with Flutter and Material Design 3.
It helps users track expenses/income, monitor budgets, and understand spending trends with clear analytics.

## ✨ Highlights

- Material Design 3 (Material You)
- Dynamic color support when available
- Expense & income tracking
- Category-level monthly budget progress
- Weekly/monthly analytics charts
- Local persistence (SQLite)
- Feature-first architecture with Riverpod

## 🧱 Tech Stack

- **Flutter** (stable)
- **Material 3** (`useMaterial3: true`)
- **Riverpod** (state management)
- **GoRouter** (navigation)
- **SQLite** (`sqlite3` package)
- **fl_chart** (analytics visuals)

## 📂 Project Structure

```text
lib/
  core/
    db/
    router/
    theme/
  design_system/
    components/
    tokens/
  features/
    home/
    transactions/
```

## 🚀 Getting Started

### Prerequisites

- Flutter SDK (stable)
- Linux desktop dependencies (for `-d linux`)

### Run locally

```bash
export PATH=/home/diego/clawd/.tooling/flutter/bin:$PATH
cd /home/diego/Proyectos/nexo
flutter pub get
flutter run -d linux
```

## 🧪 Quality

```bash
flutter analyze
flutter test
```

## 🤝 Contributing

Please read [CONTRIBUTING.md](./CONTRIBUTING.md) before opening a PR.

## 🔒 Security

If you discover a security issue, please read [SECURITY.md](./SECURITY.md).

## 📜 License

This project is licensed under the [MIT License](./LICENSE).
