<?php
// backup_csv_import.php

// 配置
$host     = "localhost";       // 数据库地址
$user     = "xinayang";            // 数据库用户名
$password = "mYMbSLAL7GicSF26";          // 数据库密码
$dbname   = "xinayang";   // 数据库名
$table    = "mod_goods";       // 目标表
$csvFile  = "/www/wwwroot/converted_merged_superpharm_products.csv"; // CSV 文件路径

// 创建数据库连接
$conn = new mysqli($host, $user, $password, $dbname);
if ($conn->connect_error) {
    die("连接失败: " . $conn->connect_error . "\n");
}
$conn->set_charset("utf8");

// 打开 CSV 文件
if (!file_exists($csvFile)) {
    die("CSV 文件不存在: $csvFile\n");
}
if (($handle = fopen($csvFile, "r")) === FALSE) {
    die("无法打开 CSV 文件: $csvFile\n");
}

// 读取表头
$header = fgetcsv($handle);
if (!$header) {
    die("CSV 文件为空或表头读取失败\n");
}

// 去掉 BOM（如果存在）
$header[0] = preg_replace('/^\xEF\xBB\xBF/', '', $header[0]);

// 开始导入数据
$inserted = 0;
while (($row = fgetcsv($handle)) !== FALSE) {
    $values = array_map(function($val) use ($conn) {
        return "'" . $conn->real_escape_string($val) . "'";
    }, $row);

    $sql = "INSERT INTO `$table` (`" . implode("`,`", $header) . "`) VALUES (" . implode(",", $values) . ")";
    if ($conn->query($sql) === TRUE) {
        $inserted++;
    } else {
        echo "导入失败: " . $conn->error . "\nSQL: $sql\n";
    }
}

fclose($handle);
$conn->close();

echo "导入完成，共 $inserted 条记录插入成功。\n";