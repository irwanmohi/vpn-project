import pymysql
from flask import current_app, g


def get_db():
    if 'db' not in g:
        g.db = pymysql.connect(
            host=current_app.config['MYSQL_HOST'],
            user=current_app.config['MYSQL_USER'],
            password=current_app.config['MYSQL_PASSWORD'],
            database=current_app.config['MYSQL_DB'],
            port=current_app.config['MYSQL_PORT'],
            cursorclass=pymysql.cursors.DictCursor,
            charset='utf8mb4',
            autocommit=False,
        )
    return g.db


def close_db(e=None):
    db = g.pop('db', None)
    if db is not None:
        db.close()


def query(sql, args=None, one=False, commit=False):
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.execute(sql, args or ())
            if commit:
                db.commit()
                return cur.lastrowid
            if one:
                return cur.fetchone()
            return cur.fetchall()
    except Exception:
        db.rollback()
        raise


def execute_many(sql, args_list):
    db = get_db()
    try:
        with db.cursor() as cur:
            cur.executemany(sql, args_list)
        db.commit()
    except Exception:
        db.rollback()
        raise
