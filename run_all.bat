@echo off
set SERVERS=ES-HAITD16 ES-HAITD16\SQL1 ES-HAITD16\SQL2 ES-HAITD16\SQL3

for %%S in (%SERVERS%) do (
    echo Đang thực thi trên %%S...
    sqlcmd -S "%%S" -E -i "alter_tables.sql"
    sqlcmd -S "%%S" -E -i "04_Role_PhanQuyen.sql"
    sqlcmd -S "%%S" -E -i "06_SP_SaoKeTaiKhoan.sql"
    sqlcmd -S "%%S" -E -i "07_SP_ChuyenTien.sql"
    sqlcmd -S "%%S" -E -i "08_SP_ChuyenNhanVien.sql"
    sqlcmd -S "%%S" -E -i "sp_Login_App.sql"
)
echo Hoan thanh!
