<?php
$host     = 'localhost';
$database = 'database_name';
$username = 'your_username';
$password = 'your_password';

try {
    // Membuat koneksi ke database menggunakan PDO
    $db = new PDO("mysql:host=$host;dbname=$database;charset=utf8mb4", $username, $password);
    
    // Mengatur mode error PDO ke Exception
    $db->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
    
    echo "<h1 style='color:green;'>Sukses: Koneksi ke database berhasil!</h1>";
} catch (PDOException $e) {
    // Menampilkan pesan jika koneksi gagal
    echo "<h1 style='color:red;'>Gagal: " . $e->getMessage() . "</h1>";
}
?>
