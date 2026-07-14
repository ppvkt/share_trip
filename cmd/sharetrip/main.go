package main

import (
	"context"
	"log"

	"github.com/gofiber/fiber/v2"
	"github.com/joho/godotenv"
	"ppvkt.com/share_trip/config"
	"ppvkt.com/share_trip/internal/storage"
)

func main() {
	if err := godotenv.Load(); err != nil {
		log.Fatal(".env file not found! Please create .env file")
	}

	ctx := context.Background()
	cfg := storage.Config{
		Host:     config.Env("DB_HOST", "localhost"),
		Port:     config.EnvInt("DB_PORT", 5432),
		User:     config.Env("DB_USER", ""),
		Password: config.Env("DB_PASSWORD", ""),
		DBName:   config.Env("DB_NAME", ""),
		SSLMode:  config.Env("DB_SSLMODE", "disable"),
	}

	pool, err := storage.NewPool(ctx, cfg.DSN())
	if err != nil {
		log.Fatal(err)
	}

	defer pool.Close()

	app := fiber.New()
	app.Get("/ready", func(c *fiber.Ctx) error {
		if err := pool.Ping(ctx); err != nil {
			return c.Status(fiber.StatusServiceUnavailable).JSON(fiber.Map{
				"status": "not ready",
				"error":  err.Error(),
			})
		}
		return c.JSON(fiber.Map{
			"status": "ok",
			"db":     "connected",
		})
	})

	err = app.Listen(":8080")
	if err != nil {
		log.Fatal(err)
	}
}
