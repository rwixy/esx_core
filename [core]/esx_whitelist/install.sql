-- ESX Whitelist System Database Tables
-- Note: These tables are created automatically by the script on startup
-- This file is provided for manual setup or debugging purposes

CREATE TABLE IF NOT EXISTS `whitelist` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `player_name` VARCHAR(255) COLLATE utf8mb4_unicode_ci DEFAULT 'Unknown',
    `whitelisted` TINYINT(1) NOT NULL DEFAULT 0,
    `added_by` VARCHAR(255) COLLATE utf8mb4_unicode_ci DEFAULT NULL,
    `added_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    KEY `idx_whitelisted` (`whitelisted`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

CREATE TABLE IF NOT EXISTS `whitelist_identifiers` (
    `id` INT AUTO_INCREMENT PRIMARY KEY,
    `whitelist_id` INT NOT NULL,
    `type` VARCHAR(32) NOT NULL,
    `identifier` VARCHAR(255) NOT NULL COLLATE utf8mb4_bin,
    FOREIGN KEY (`whitelist_id`) REFERENCES `whitelist`(`id`) ON DELETE CASCADE,
    UNIQUE KEY `unique_identifier` (`type`, `identifier`),
    KEY `idx_identifier` (`identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;