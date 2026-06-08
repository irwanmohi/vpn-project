import os
from datetime import datetime
from flask import Flask, redirect, url_for
from config import Config
from services.database import close_db


def create_app(config_class=Config):
    app = Flask(__name__)
    app.config.from_object(config_class)

    app.teardown_appcontext(close_db)

    @app.template_filter('datetimefmt')
    def datetimefmt(value, fmt='%Y-%m-%d %H:%M'):
        if value is None:
            return 'N/A'
        return value.strftime(fmt)

    @app.template_filter('bytes_fmt')
    def bytes_fmt(value):
        value = value or 0
        for unit in ('B', 'KB', 'MB', 'GB', 'TB'):
            if value < 1024:
                return f'{value:.1f} {unit}'
            value /= 1024
        return f'{value:.1f} PB'

    @app.template_filter('timeago')
    def timeago(ts):
        if not ts:
            return 'never'
        now   = datetime.utcnow()
        delta = now - datetime.utcfromtimestamp(ts)
        secs  = int(delta.total_seconds())
        if secs < 60:
            return f'{secs}s ago'
        if secs < 3600:
            return f'{secs // 60}m ago'
        if secs < 86400:
            return f'{secs // 3600}h ago'
        return f'{secs // 86400}d ago'

    from routes.auth  import auth_bp
    from routes.admin import admin_bp
    from routes.user  import user_bp

    app.register_blueprint(auth_bp)
    app.register_blueprint(admin_bp, url_prefix='/admin')
    app.register_blueprint(user_bp,  url_prefix='/user')

    @app.route('/')
    def index():
        return redirect(url_for('auth.login'))

    return app


if __name__ == '__main__':
    application = create_app()
    application.run(debug=True, host='0.0.0.0', port=5000)
