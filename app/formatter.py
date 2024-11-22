import html
import re


class OutputFormatter:
    """Форматирование вывода команды в читабельный вид."""
    @staticmethod
    def clean_terminal_output(output: str) -> str:
        """
        Очистка вывода от терминальных escape-последовательностей 
        с сохранением важной информации
        """
        # Удаление ANSI escape-последовательностей
        ansi_escape = re.compile(r'\x1B[@-_][0-?]*[ -/]*[@-~]')
        output = ansi_escape.sub('', output)

        # Удаление специальных управляющих символов
        output = re.sub(r'\[K', '', output)
        output = re.sub(r'\x1b\[[0-9;]*[mz]', '', output)

        # Разбить на строки и очистить каждую
        cleaned_lines = []
        for line in output.split('\n'):
            # Убрать лишние пробелы в начале и конце
            line = line.strip()
            
            # Пропускаем пустые строки и разделители
            if line and not re.match(r'^-+$', line):
                # Специальная обработка строк с количеством
                if 'список разблокировки' in line.lower():
                    # Сохраняем строку с количеством, но очищаем от лишних символов
                    count_match = re.search(r'содержит\s+(\d+)\s+записей', line)
                    if count_match:
                        line = f"Список разблокировки содержит {count_match.group(1)} записей:"
                
                # HTML-экранирование для безопасности
                line = html.escape(line)
                cleaned_lines.append(line)

        return '\n'.join(cleaned_lines)