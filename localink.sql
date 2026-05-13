-- localink.sql - Database Schema for URL Shortener
-- 
-- Creates the database and tables needed for the URL shortener.
-- Run this to set up the MySQL database.

-- Create database if not exists
CREATE DATABASE IF NOT EXISTS localink CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Use the database
USE localink;

-- Create URLs table
CREATE TABLE IF NOT EXISTS urls (
    id INT AUTO_INCREMENT PRIMARY KEY,
    short_id VARCHAR(10) NOT NULL UNIQUE COMMENT '6-10 character Base62 short ID',
    original_url TEXT NOT NULL COMMENT 'Original URL that was shortened',
    created_at DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP COMMENT 'Timestamp of creation',
    INDEX idx_short_id (short_id),
    INDEX idx_created_at (created_at)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci COMMENT='Shortened URLs table';