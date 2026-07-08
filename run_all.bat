@echo off
cd /d "%~dp0"
set SERVERS=ES-HAITD16 ES-HAITD16\SQL1 ES-HAITD16\SQL2 ES-HAITD16\SQL3

for %%S in (%SERVERS%) do (
    echo Dang thuc thi tren %%S...
    sqlcmd -S "%%S" -E -i "sql\setup\alter_tables.sql"
    sqlcmd -S "%%S" -E -i "sql\setup\04_Role_PhanQuyen.sql"
    sqlcmd -S "%%S" -E -i "sql\stored_procedures\06_SP_SaoKeTaiKhoan.sql"
    sqlcmd -S "%%S" -E -i "sql\stored_procedures\07_SP_ChuyenTien.sql"
    sqlcmd -S "%%S" -E -i "sql\stored_procedures\08_SP_ChuyenNhanVien.sql"
    sqlcmd -S "%%S" -E -i "sql\stored_procedures\sp_Login_App.sql"
    sqlcmd -S "%%S" -E -i "sql\stored_procedures\11_SP_TaoTaiKhoan.sql"
    sqlcmd -S "%%S" -E -i "sql\stored_procedures\12_SP_DanhSachTaiKhoan.sql"
    sqlcmd -S "%%S" -E -i "sql\stored_procedures\13_SP_SaoKeToanBo.sql"
    sqlcmd -S "%%S" -E -i "sql\stored_procedures\14_SP_TaiKhoanKhachHang.sql"
)
echo Hoan thanh!
