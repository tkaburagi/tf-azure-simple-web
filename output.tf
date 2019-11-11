output "alb_dns" {
    value = aws_alb.web_alb.dns_name
}
