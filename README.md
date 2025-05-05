# Toppin Rails

A Ruby on Rails backend application for managing a dating platform. This API provides all the necessary endpoints for user matching, profile management, messaging, and real-time notifications.

## Requirements

- Ruby 3.0.6
- MySQL
- Node.js and Yarn
- Docker (optional)

## System Dependencies

- MySQL Server
- Redis (optional, for Action Cable)

## Setup Instructions

### Local Development

1. Clone the repository:

```bash
git clone [repository-url]
cd toppin_rails
```

2. Install Ruby dependencies:

```bash
bundle install
```

3. Install JavaScript dependencies:

```bash
yarn install
```

4. Configure the database:

```bash
cp config/database.yml.example config/database.yml
# Edit config/database.yml with your database credentials
```

5. Create and migrate the database:

```bash
rails db:create db:migrate
```

6. Set up environment variables:

```bash
cp .env.example .env
# Edit .env with your configuration
```

7. Start the development server:

```bash
rails server
```

### Docker Setup

1. Build and start the containers:

```bash
docker-compose up --build
```

The application will be available at `http://localhost:3000`

## Testing

Run the test suite:

```bash
rails test
```

## Key Features

- User authentication with Devise and JWT
- File uploads with Carrierwave and AWS S3
- Email notifications with Mailjet
- SMS notifications with Twilio
- Geocoding capabilities
- Push notifications support
- API endpoints with CORS support
- Pagination and search functionality

## Project Structure

- `app/` - Application code
- `config/` - Configuration files
- `db/` - Database files and migrations
- `lib/` - Library modules
- `public/` - Public assets
- `test/` - Test files
- `vendor/` - Vendor assets

## Deployment

The application can be deployed using Docker:

```bash
docker-compose -f docker-compose.prod.yml up --build
```

## Contributing

1. Fork the repository
2. Create your feature branch
3. Commit your changes
4. Push to the branch
5. Create a new Pull Request

## License

[Add your license information here]
