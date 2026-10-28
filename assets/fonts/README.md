# Fonts cho Orders/Notifications

Font nguyên bản từ Google Fonts, tải ngày 10/10/2026; không sửa nội dung font.

- [Inter variable](https://github.com/google/fonts/blob/main/ofl/inter/Inter%5Bopsz%2Cwght%5D.ttf): đổi tên file local thành `Inter-Variable.ttf` để tránh ký tự đặc biệt trong asset path.
- [Barlow Condensed Bold](https://github.com/google/fonts/blob/main/ofl/barlowcondensed/BarlowCondensed-Bold.ttf).
- Giấy phép SIL Open Font License 1.1 cùng copyright: `Inter-OFL.txt`, `BarlowCondensed-OFL.txt`.

Hai license được đóng gói trong Flutter assets và đăng ký với `LicenseRegistry` khi theme feature được dùng. Không thêm package hoặc thay font của AppTheme toàn nhóm.
