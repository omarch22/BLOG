#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Administración de un blog sobre Oracle (Bases de Datos Avanzadas - Proyecto 1ª Evaluación).

Toda la lógica de datos está en procedimientos y funciones PL/SQL (paquetes pkg_*).
Esta aplicación NO contiene SQL: únicamente los invoca con callproc / callfunc.

Configuración por variables de entorno (opcionales):
    BLOG_USER      usuario Oracle           (por defecto: blog)
    BLOG_PASSWORD  contraseña               (si falta, se pregunta)
    BLOG_DSN       cadena de conexión       (por defecto: localhost:1521/XEPDB1)

Requisito:  pip install oracledb
"""
import getpass
import os
import re
import sys
from datetime import datetime

import oracledb

conn = None  # conexión global, se abre en main()


# =====================================================================
# Utilidades de acceso a PL/SQL
# =====================================================================
class NotFound(Exception):
    """El registro pedido no existe."""


def connect():
    user = os.getenv("BLOG_USER", "system")          # antes "blog"
    password = os.getenv("BLOG_PASSWORD", "oracle")  # antes preguntaba la contraseña
    dsn = os.getenv("BLOG_DSN", "localhost:1521/XEPDB1")
    return oracledb.connect(user=user, password=password, dsn=dsn)

def friendly(exc):
    """Mensaje legible de un error de Oracle (limpia 'ORA-20001:' de los errores propios)."""
    err = exc.args[0]
    text = getattr(err, "message", str(err))
    code = getattr(err, "code", None)
    if code and 20000 <= code <= 20999:
        return re.sub(r"^ORA-\d+:\s*", "", text.splitlines()[0])
    return text.strip()


def call_proc(name, *params):
    """Llama a un procedimiento almacenado sin parámetros de salida."""
    with conn.cursor() as cur:
        cur.callproc(name, list(params))


def call_proc_out_id(name, *params):
    """Llama a un procedimiento cuyo ÚLTIMO parámetro es un OUT numérico (el id creado)."""
    with conn.cursor() as cur:
        new_id = cur.var(int)
        cur.callproc(name, [*params, new_id])
        return int(new_id.getvalue())


def call_func(name, return_type, *params):
    """Llama a una función escalar."""
    with conn.cursor() as cur:
        return cur.callfunc(name, return_type, list(params))


def _plain(row):
    """Convierte LOB, fechas y NULL en valores imprimibles."""
    out = []
    for v in row:
        if isinstance(v, oracledb.LOB):
            v = v.read()
        elif isinstance(v, datetime):
            v = v.strftime("%d/%m/%Y %H:%M")
        elif v is None:
            v = ""
        out.append(v)
    return out


def call_query(name, *params):
    """Llama a una función que devuelve SYS_REFCURSOR. Devuelve (cabeceras, filas)."""
    with conn.cursor() as cur:
        ref = cur.callfunc(name, oracledb.DB_TYPE_CURSOR, list(params))
        headers = [d[0] for d in ref.description]
        rows = [_plain(r) for r in ref.fetchall()]
        ref.close()
    return headers, rows


def fetch_one(name, id_, what="El registro"):
    """Devuelve la primera fila de una función get_* como diccionario."""
    headers, rows = call_query(name, id_)
    if not rows:
        raise NotFound(f"{what} con id {id_} no existe.")
    return dict(zip((h.lower() for h in headers), rows[0]))


# =====================================================================
# Entrada / salida por consola
# =====================================================================
def print_table(headers, rows, max_width=45):
    if not rows:
        print("  (sin resultados)")
        return
    cells = []
    for r in rows:
        line = []
        for c in r:
            s = str(c).replace("\n", " ")
            line.append(s if len(s) <= max_width else s[: max_width - 1] + "…")
        cells.append(line)
    heads = [h.lower() for h in headers]
    widths = [max(len(h), *(len(r[i]) for r in cells)) for i, h in enumerate(heads)]
    print("  " + "  ".join(h.ljust(w) for h, w in zip(heads, widths)))
    print("  " + "  ".join("-" * w for w in widths))
    for r in cells:
        print("  " + "  ".join(c.ljust(w) for c, w in zip(r, widths)))
    print(f"  ({len(rows)} fila(s))")


def show(name, *params):
    headers, rows = call_query(name, *params)
    print_table(headers, rows)


def ask(prompt, default=None, required=True):
    suffix = f" [{default}]" if default not in (None, "") else ""
    while True:
        value = input(f"{prompt}{suffix}: ").strip()
        if not value and default is not None:
            return default
        if value or not required:
            return value
        print("  Este campo es obligatorio.")


def ask_int(prompt):
    while True:
        value = input(f"{prompt}: ").strip()
        if value.isdigit():
            return int(value)
        print("  Introduce un número entero.")


def ask_text(prompt, default=None):
    """Texto multilínea: termina con una línea vacía. Con default, vacío = conservar."""
    hint = ("termina con una línea vacía; si no escribes nada se conserva el actual"
            if default else "termina con una línea vacía")
    print(f"{prompt} ({hint}):")
    lines = []
    while True:
        line = input("  > ")
        if not line:
            break
        lines.append(line)
    text = "\n".join(lines).strip()
    if text:
        return text
    if default:
        return default
    print("  Este campo es obligatorio.")
    return ask_text(prompt, default)


def confirm(prompt):
    return input(f"{prompt} (s/N): ").strip().lower() == "s"


def menu(title, options, back="Volver"):
    while True:
        print(f"\n=== {title} ===")
        for i, (label, _) in enumerate(options, 1):
            print(f"  {i}. {label}")
        print(f"  0. {back}")
        choice = input("Opción: ").strip()
        if choice == "0":
            return
        if not (choice.isdigit() and 1 <= int(choice) <= len(options)):
            print("  Opción no válida.")
            continue
        try:
            options[int(choice) - 1][1]()
        except oracledb.DatabaseError as exc:
            print(f"  ✖ {friendly(exc)}")
        except NotFound as exc:
            print(f"  ✖ {exc}")


# =====================================================================
# USUARIOS
# =====================================================================
def user_add():
    name = ask("Nombre")
    email = ask("Email")
    uid = call_proc_out_id("pkg_users.add_user", name, email)
    print(f"  ✔ Usuario creado con id {uid}")


def user_list():
    show("pkg_users.list_users")


def user_update():
    uid = ask_int("Id del usuario")
    cur = fetch_one("pkg_users.get_user", uid, "El usuario")
    call_proc("pkg_users.update_user", uid,
              ask("Nombre", cur["name"]), ask("Email", cur["email"]))
    print("  ✔ Usuario actualizado")


def user_delete():
    uid = ask_int("Id del usuario")
    cur = fetch_one("pkg_users.get_user", uid, "El usuario")
    if confirm(f"¿Borrar a {cur['name']} junto con sus artículos y comentarios?"):
        call_proc("pkg_users.delete_user", uid)
        print("  ✔ Usuario eliminado")


def user_count_articles():
    uid = ask_int("Id del usuario")
    total = call_func("pkg_users.count_articles", int, uid)
    print(f"  El usuario {uid} ha publicado {total} artículo(s).")


def users_menu():
    menu("USUARIOS", [
        ("Alta de usuario", user_add),
        ("Listar usuarios", user_list),
        ("Modificar usuario", user_update),
        ("Eliminar usuario", user_delete),
        ("Contar artículos de un usuario", user_count_articles),
    ])


# =====================================================================
# ETIQUETAS y CATEGORÍAS (misma estructura, se generan con una fábrica)
# =====================================================================
def taxonomy_menu(title, pkg, one, many, label):
    def add():
        name = ask("Nombre")
        url = ask("URL (vacío = generar a partir del nombre)", required=False) or None
        new_id = call_proc_out_id(f"{pkg}.add_{one}", name, url)
        print(f"  ✔ {label} creada con id {new_id}")

    def lst():
        show(f"{pkg}.list_{many}")

    def update():
        tid = ask_int(f"Id de la {label.lower()}")
        cur = fetch_one(f"{pkg}.get_{one}", tid, f"La {label.lower()}")
        call_proc(f"{pkg}.update_{one}", tid,
                  ask("Nombre", cur["name"]), ask("URL", cur["url"]))
        print(f"  ✔ {label} actualizada")

    def delete():
        tid = ask_int(f"Id de la {label.lower()}")
        cur = fetch_one(f"{pkg}.get_{one}", tid, f"La {label.lower()}")
        if confirm(f"¿Borrar '{cur['name']}'? (se desvincula de sus artículos)"):
            call_proc(f"{pkg}.delete_{one}", tid)
            print(f"  ✔ {label} eliminada")

    def count():
        tid = ask_int(f"Id de la {label.lower()}")
        total = call_func(f"{pkg}.count_articles", int, tid)
        print(f"  Tiene {total} artículo(s) asociado(s).")

    menu(title, [
        (f"Alta de {label.lower()}", add),
        (f"Listar {many}", lst),
        (f"Modificar {label.lower()}", update),
        (f"Eliminar {label.lower()}", delete),
        ("Contar artículos asociados", count),
    ])


def tags_menu():
    taxonomy_menu("ETIQUETAS", "pkg_tags", "tag", "tags", "Etiqueta")


def categories_menu():
    taxonomy_menu("CATEGORÍAS", "pkg_categories", "category", "categories", "Categoría")


# =====================================================================
# ARTÍCULOS
# =====================================================================
def article_add():
    print("Usuarios disponibles:")
    show("pkg_users.list_users")
    uid = ask_int("Id del autor")
    title = ask("Título")
    content = ask_text("Contenido")
    aid = call_proc_out_id("pkg_articles.add_article", title, content, uid)
    print(f"  ✔ Artículo creado con id {aid}")


def article_list():
    show("pkg_articles.list_articles")


def article_view():
    aid = ask_int("Id del artículo")
    a = fetch_one("pkg_articles.get_article", aid, "El artículo")
    _, tags = call_query("pkg_articles.get_tags", aid)
    _, cats = call_query("pkg_articles.get_categories", aid)
    print(f"\n  {a['title'].upper()}")
    print(f"  Por {a['author']} — {a['article_date']}")
    print(f"  Etiquetas:   {', '.join(t[1] for t in tags) or '—'}")
    print(f"  Categorías:  {', '.join(c[1] for c in cats) or '—'}\n")
    print(a["content"])
    print(f"\n  Comentarios ({a['n_comments']}):")
    show("pkg_comments.list_by_article", aid)


def article_update():
    aid = ask_int("Id del artículo")
    cur = fetch_one("pkg_articles.get_article", aid, "El artículo")
    title = ask("Título", cur["title"])
    content = ask_text("Contenido", cur["content"])
    call_proc("pkg_articles.update_article", aid, title, content)
    print("  ✔ Artículo actualizado")


def article_delete():
    aid = ask_int("Id del artículo")
    cur = fetch_one("pkg_articles.get_article", aid, "El artículo")
    if confirm(f"¿Borrar '{cur['title']}' y sus {cur['n_comments']} comentario(s)?"):
        call_proc("pkg_articles.delete_article", aid)
        print("  ✔ Artículo eliminado")


def article_by_user():
    show("pkg_articles.list_by_user", ask_int("Id del usuario"))


def article_by_tag():
    show("pkg_tags.list_tags")
    show("pkg_articles.list_by_tag", ask_int("Id de la etiqueta"))


def article_by_category():
    show("pkg_categories.list_categories")
    show("pkg_articles.list_by_category", ask_int("Id de la categoría"))


def article_search():
    show("pkg_articles.search_articles", ask("Texto a buscar (título o contenido)"))


def article_add_tag():
    aid = ask_int("Id del artículo")
    show("pkg_tags.list_tags")
    call_proc("pkg_articles.add_tag", aid, ask_int("Id de la etiqueta a añadir"))
    print("  ✔ Etiqueta añadida")


def article_remove_tag():
    aid = ask_int("Id del artículo")
    show("pkg_articles.get_tags", aid)
    call_proc("pkg_articles.remove_tag", aid, ask_int("Id de la etiqueta a quitar"))
    print("  ✔ Etiqueta quitada")


def article_add_category():
    aid = ask_int("Id del artículo")
    show("pkg_categories.list_categories")
    call_proc("pkg_articles.add_category", aid, ask_int("Id de la categoría a añadir"))
    print("  ✔ Categoría añadida")


def article_remove_category():
    aid = ask_int("Id del artículo")
    show("pkg_articles.get_categories", aid)
    call_proc("pkg_articles.remove_category", aid, ask_int("Id de la categoría a quitar"))
    print("  ✔ Categoría quitada")


def articles_menu():
    menu("ARTÍCULOS", [
        ("Alta de artículo", article_add),
        ("Listar artículos", article_list),
        ("Ver artículo completo", article_view),
        ("Modificar artículo", article_update),
        ("Eliminar artículo", article_delete),
        ("Listar artículos de un usuario", article_by_user),
        ("Listar artículos por etiqueta", article_by_tag),
        ("Listar artículos por categoría", article_by_category),
        ("Buscar artículos por texto", article_search),
        ("Añadir etiqueta a un artículo", article_add_tag),
        ("Quitar etiqueta de un artículo", article_remove_tag),
        ("Añadir categoría a un artículo", article_add_category),
        ("Quitar categoría de un artículo", article_remove_category),
    ])


# =====================================================================
# COMENTARIOS
# =====================================================================
def comment_add():
    aid = ask_int("Id del artículo")
    print("Usuarios disponibles:")
    show("pkg_users.list_users")
    uid = ask_int("Id del usuario que comenta")
    name = ask("Comentario")
    url = ask("URL (opcional)", required=False) or None
    cid = call_proc_out_id("pkg_comments.add_comment", name, url, uid, aid)
    print(f"  ✔ Comentario creado con id {cid}")


def comment_list_by_article():
    show("pkg_comments.list_by_article", ask_int("Id del artículo"))


def comment_list_by_user():
    show("pkg_comments.list_by_user", ask_int("Id del usuario"))


def comment_update():
    cid = ask_int("Id del comentario")
    cur = fetch_one("pkg_comments.get_comment", cid, "El comentario")
    name = ask("Comentario", cur["name"])
    url = ask("URL", cur["url"], required=False) or None
    call_proc("pkg_comments.update_comment", cid, name, url)
    print("  ✔ Comentario actualizado")


def comment_delete():
    cid = ask_int("Id del comentario")
    fetch_one("pkg_comments.get_comment", cid, "El comentario")
    if confirm("¿Borrar el comentario?"):
        call_proc("pkg_comments.delete_comment", cid)
        print("  ✔ Comentario eliminado")


def comment_count():
    aid = ask_int("Id del artículo")
    total = call_func("pkg_articles.count_comments", int, aid)
    print(f"  El artículo {aid} tiene {total} comentario(s).")


def comments_menu():
    menu("COMENTARIOS", [
        ("Alta de comentario", comment_add),
        ("Listar comentarios de un artículo", comment_list_by_article),
        ("Listar comentarios de un usuario", comment_list_by_user),
        ("Modificar comentario", comment_update),
        ("Eliminar comentario", comment_delete),
        ("Contar comentarios de un artículo", comment_count),
    ])


# =====================================================================
# Programa principal
# =====================================================================
def main():
    global conn
    try:
        conn = connect()
    except oracledb.Error as exc:
        print(f"No se pudo conectar a Oracle: {friendly(exc)}")
        sys.exit(1)

    print(f"Conectado a Oracle {conn.version}")
    try:
        menu("BLOG · MENÚ PRINCIPAL", [
            ("Usuarios", users_menu),
            ("Artículos", articles_menu),
            ("Comentarios", comments_menu),
            ("Etiquetas", tags_menu),
            ("Categorías", categories_menu),
        ], back="Salir")
    except (KeyboardInterrupt, EOFError):
        print()
    finally:
        conn.close()
        print("Hasta pronto.")


if __name__ == "__main__":
    main()